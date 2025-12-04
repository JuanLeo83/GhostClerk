//
//  FileProcessor.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import os.log

/// Main orchestrator for the file processing pipeline.
/// Coordinates between FolderMonitor, ProcessingQueue, and future AI/Rules components.
final class FileProcessor: @unchecked Sendable {
    
    // MARK: - Singleton
    
    static let shared = FileProcessor()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.ghostclerk.app", category: "FileProcessor")
    private let fileManager = FileManager.default
    
    /// Retry queue for locked/incomplete files
    private let retryQueue = RetryQueue()
    
    /// Track processed files to avoid duplicates (file path -> last modification date)
    private var processedFiles: [String: Date] = [:]
    private let processedFilesLock = NSLock()
    
    /// Extensions to ignore (temporary download files)
    private let temporaryExtensions: Set<String> = [
        "crdownload",   // Chrome
        "part",         // Firefox
        "download",     // Safari
        "tmp",          // Generic temp
        "partial"       // Generic partial
    ]
    
    /// Extensions to whitelist (installers/apps - don't process)
    private let whitelistedExtensions: Set<String> = [
        "dmg",
        "pkg",
        "app",
        "iso"
    ]
    
    /// Minimum file age in seconds before processing (debounce)
    private let minimumFileAge: TimeInterval = 2.0
    
    /// Callback for logging activity
    var onActivityLogged: ((ActivityLog) -> Void)?
    
    /// Active rules for file classification (set from AppState)
    var activeRules: [Rule] = []
    
    /// Returns the real Downloads folder URL (not sandbox container)
    private static var realDownloadsURL: URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        if homeDir.path.contains("/Library/Containers/") {
            let realHome = URL(fileURLWithPath: NSHomeDirectory().components(separatedBy: "/Library/Containers/").first ?? NSHomeDirectory())
            return realHome.appendingPathComponent("Downloads")
        }
        return homeDir.appendingPathComponent("Downloads")
    }
    
    // MARK: - Initialization
    
    private init() {
        // Start retry queue with callback
        Task {
            await retryQueue.start { [weak self] url in
                self?.attemptProcessFile(url) ?? false
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Stops the retry queue when monitoring is paused
    func stopRetryQueue() {
        Task {
            await retryQueue.stop()
        }
    }
    
    /// Restarts the retry queue when monitoring resumes
    func startRetryQueue() {
        Task {
            await retryQueue.start { [weak self] url in
                self?.attemptProcessFile(url) ?? false
            }
        }
    }
    
    /// Scans the Downloads folder and enqueues new files for processing.
    func scanDownloadsFolder() {
        let downloadsURL = Self.realDownloadsURL
        
        logger.info("Scanning Downloads folder: \(downloadsURL.path)")
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            
            let filesToProcess = contents.filter { url in
                shouldProcessFile(url)
            }
            
            logger.info("Found \(filesToProcess.count) files to process out of \(contents.count) total")
            
            for file in filesToProcess {
                processFile(file)
            }
            
        } catch {
            logger.error("Failed to scan Downloads folder: \(error.localizedDescription)")
        }
    }
    
    /// Handles a single file detected by FolderMonitor
    func handleDetectedFile(_ url: URL) {
        guard shouldProcessFile(url) else {
            return
        }
        
        processFile(url)
    }
    
    // MARK: - File Filtering
    
    /// Determines if a file should be processed based on various criteria.
    private func shouldProcessFile(_ url: URL) -> Bool {
        // Must be a file, not a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        
        let ext = url.pathExtension.lowercased()
        
        // Skip temporary download files
        if temporaryExtensions.contains(ext) {
            logger.debug("Skipping temporary file: \(url.lastPathComponent)")
            logActivity(fileName: url.lastPathComponent, action: .skipped, status: .success, details: "Temporary download file")
            return false
        }
        
        // Skip whitelisted files (installers/apps)
        if whitelistedExtensions.contains(ext) {
            logger.debug("Skipping whitelisted file: \(url.lastPathComponent)")
            logActivity(fileName: url.lastPathComponent, action: .whitelisted, status: .success, details: "Installer/App file")
            return false
        }
        
        // Check if already processed (same file, same modification date)
        if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            let age = Date().timeIntervalSince(modDate)
            
            // Check file age (debounce recently created files)
            if age < minimumFileAge {
                logger.debug("File too new, queueing for retry: \(url.lastPathComponent) (age: \(age)s)")
                Task { await retryQueue.enqueue(url) }
                return false
            }
            
            // Check if already processed with same modification date
            processedFilesLock.lock()
            let lastProcessed = processedFiles[url.path]
            processedFilesLock.unlock()
            
            if let lastProcessed = lastProcessed, lastProcessed == modDate {
                logger.debug("File already processed, skipping: \(url.lastPathComponent)")
                return false
            }
        }
        
        // Check if file is locked/being written
        if isFileLocked(url) {
            logger.debug("File is locked, queueing for retry: \(url.lastPathComponent)")
            Task { await retryQueue.enqueue(url) }
            logActivity(fileName: url.lastPathComponent, action: .scanned, status: .retrying, details: "File locked, queued for retry")
            return false
        }
        
        return true
    }
    
    /// Checks if a file is currently locked (being written to).
    private func isFileLocked(_ url: URL) -> Bool {
        // Try to open the file for reading - if it fails, it might be locked
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return true
        }
        try? fileHandle.close()
        return false
    }
    
    // MARK: - File Processing
    
    /// Attempt to process a file (used by retry queue).
    /// Returns true if processing succeeded, false if it should be retried.
    private func attemptProcessFile(_ url: URL) -> Bool {
        // Revalidate file state
        guard fileManager.fileExists(atPath: url.path) else {
            return true // File gone, consider it "handled"
        }
        
        // Skip temp/whitelisted (shouldn't happen, but defensive)
        let ext = url.pathExtension.lowercased()
        if temporaryExtensions.contains(ext) || whitelistedExtensions.contains(ext) {
            return true
        }
        
        // Check if still locked
        if isFileLocked(url) {
            logger.debug("File still locked on retry: \(url.lastPathComponent)")
            return false
        }
        
        // Check age again
        if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            let age = Date().timeIntervalSince(modDate)
            if age < minimumFileAge {
                return false
            }
        }
        
        // Process it
        processFile(url)
        return true
    }
    
    /// Main processing logic for a single file.
    private func processFile(_ url: URL) {
        logger.info("Processing: \(url.lastPathComponent)")
        
        // Verify file still exists
        guard fileManager.fileExists(atPath: url.path) else {
            logger.warning("File no longer exists: \(url.lastPathComponent)")
            return
        }
        
        // Mark as processed with current modification date
        if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            processedFilesLock.lock()
            processedFiles[url.path] = modDate
            processedFilesLock.unlock()
        }
        
        // Remove from retry queue if present
        Task { await retryQueue.dequeue(url) }
        
        // Log that we scanned the file
        logActivity(fileName: url.lastPathComponent, action: .scanned, status: .success)
        
        // Calculate file hash for duplicate detection
        if let hash = FileHasher.sha256(of: url) {
            logger.debug("File hash: \(hash.prefix(16))...")
        }
        
        // Get active rules
        let rules = activeRules
        
        // Extract text and run inference
        Task {
            await processFileWithAI(url: url, rules: rules)
        }
        
        logger.info("Completed processing: \(url.lastPathComponent)")
    }
    
    /// Processes a file with AI inference and moves it accordingly.
    private func processFileWithAI(url: URL, rules: [Rule]) async {
        let fileName = url.lastPathComponent
        
        // Extract text content if supported
        var extractedText: String?
        if TextExtractor.shared.isSupported(url) {
            extractedText = await TextExtractor.shared.extractText(from: url)
            if let text = extractedText {
                logger.info("Extracted \(text.count) chars from: \(fileName)")
            }
        }
        
        // Combine filename + extracted text for better matching
        // The filename often contains important classification hints (e.g., "CV", "Invoice")
        let textForInference: String
        if let extracted = extractedText {
            textForInference = "FILENAME: \(fileName)\n\nCONTENT:\n\(extracted)"
        } else {
            textForInference = fileName
        }
        
        // Skip AI if no rules defined
        guard !rules.isEmpty else {
            logger.debug("No rules defined, skipping AI inference")
            return
        }
        
        // Run MLX inference to find matching rule
        do {
            if let matchedRule = try await MLXWorker.shared.infer(text: textForInference, rules: rules) {
                // Move file to rule's target folder
                logger.info("Rule matched: '\(matchedRule.naturalPrompt)' -> \(matchedRule.targetPath)")
                
                if ClerkFileManager.shared.moveFile(url, toRuleDestination: matchedRule) != nil {
                    logActivity(
                        fileName: fileName,
                        action: .moved,
                        status: .success,
                        matchedRuleId: matchedRule.id,
                        details: "Moved to \(matchedRule.targetPath)"
                    )
                } else {
                    logActivity(
                        fileName: fileName,
                        action: .moved,
                        status: .failed,
                        matchedRuleId: matchedRule.id,
                        details: "Failed to move file"
                    )
                }
            } else {
                // No rule matched - move to Review Tray
                logger.info("No rule matched for: \(fileName), moving to Review Tray")
                
                if ClerkFileManager.shared.moveToReviewTray(url) != nil {
                    logActivity(
                        fileName: fileName,
                        action: .reviewTray,
                        status: .success,
                        details: "No matching rule"
                    )
                } else {
                    logActivity(
                        fileName: fileName,
                        action: .reviewTray,
                        status: .failed,
                        details: "Failed to move to Review Tray"
                    )
                }
            }
        } catch {
            logger.error("AI inference failed for \(fileName): \(error.localizedDescription)")
            logActivity(
                fileName: fileName,
                action: .scanned,
                status: .failed,
                details: "AI inference error: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Activity Logging
    
    private func logActivity(
        fileName: String,
        action: ActionType,
        status: ActionStatus,
        matchedRuleId: UUID? = nil,
        details: String? = nil
    ) {
        let log = ActivityLog(
            fileName: fileName,
            action: action,
            status: status,
            matchedRuleId: matchedRuleId,
            details: details
        )
        
        onActivityLogged?(log)
    }
}

