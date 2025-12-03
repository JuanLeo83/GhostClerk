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
    
    private init() {}
    
    // MARK: - Public Methods
    
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
        
        // Check file age (debounce recently created files)
        if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            let age = Date().timeIntervalSince(modDate)
            if age < minimumFileAge {
                logger.debug("File too new, will retry: \(url.lastPathComponent) (age: \(age)s)")
                return false
            }
        }
        
        // Check if file is locked/being written
        if isFileLocked(url) {
            logger.debug("File is locked: \(url.lastPathComponent)")
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
    
    /// Main processing logic for a single file.
    private func processFile(_ url: URL) {
        logger.info("Processing: \(url.lastPathComponent)")
        
        // Verify file still exists
        guard fileManager.fileExists(atPath: url.path) else {
            logger.warning("File no longer exists: \(url.lastPathComponent)")
            return
        }
        
        // Log that we scanned the file
        logActivity(fileName: url.lastPathComponent, action: .scanned, status: .success)
        
        // Calculate file hash for duplicate detection
        if let hash = FileHasher.sha256(of: url) {
            logger.debug("File hash: \(hash.prefix(16))...")
        }
        
        // TODO: Phase 2 - Extract text content (PDFKit / Vision OCR)
        // TODO: Phase 3 - Send to MLX for rule matching
        // TODO: Phase 4 - Move file to destination or Review Tray
        
        logger.info("Completed processing: \(url.lastPathComponent)")
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
