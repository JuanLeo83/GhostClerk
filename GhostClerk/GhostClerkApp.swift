//
//  GhostClerkApp.swift
//  GhostClerk
//
//  Created by Juan Leo on 3/12/25.
//

import SwiftUI
import Combine
import os.log

@main
struct GhostClerkApp: App {
    
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        // Menu Bar Extra - the main entry point (no Dock icon)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // Menu bar icon with optional badge for review tray
            HStack(spacing: 2) {
                Image(systemName: appState.isMonitoring ? "eye.fill" : "eye.slash")
                if appState.reviewTrayCount > 0 {
                    Text("\(appState.reviewTrayCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
        
        // Settings window (accessible from menu bar)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State

/// Global app state shared across all views
@MainActor
final class AppState: ObservableObject {
    
    private let logger = Logger(subsystem: "com.ghostclerk.app", category: "AppState")
    
    /// Whether the folder monitor is active
    @Published var isMonitoring = false
    
    /// Current rules loaded from storage
    @Published var rules: [Rule] = []
    
    /// Recent activity logs
    @Published var recentLogs: [ActivityLog] = []
    
    /// Last detected file change
    @Published var lastChangeDetected: Date?
    
    /// Number of files pending review (triggers badge update)
    @Published var reviewTrayCount: Int = 0
    
    /// Current state of the MLX model loading
    @Published var modelLoadingState: ModelLoadingState = .idle
    
    /// Whether to wait for model before processing files (user preference)
    @AppStorage("waitForModel") var waitForModel: Bool = true
    
    /// Whether AI is enabled (false = use keyword fallback only, saves GPU resources)
    @AppStorage("aiEnabled") var aiEnabled: Bool = true
    
    /// Whether to show notifications
    @AppStorage("showNotifications") var showNotifications: Bool = true {
        didSet {
            NotificationService.shared.isEnabled = showNotifications
        }
    }
    
    /// The folder monitor instance
    private var folderMonitor: FolderMonitor?
    
    /// Timer to periodically refresh review tray count
    private var reviewTrayTimer: Timer?
    
    init() {
        setupFolderMonitor()
        setupFileProcessor()
        setupReviewTrayTimer()
        setupMLXWorkerCallback()
        setupNotifications()
        refreshReviewTrayCount()
        Task {
            await loadData()
            await preloadModel()
        }
    }
    
    // MARK: - Setup
    
    private func setupMLXWorkerCallback() {
        Task {
            await MLXWorker.shared.setStateCallback { [weak self] state in
                Task { @MainActor in
                    self?.modelLoadingState = state
                }
            }
        }
    }
    
    private func setupNotifications() {
        // Sync initial value
        NotificationService.shared.isEnabled = showNotifications
        
        // Listen for Review Tray open requests from notifications
        NotificationCenter.default.addObserver(
            forName: .openReviewTray,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.openReviewTray()
            }
        }
    }
    
    /// Preloads the model in background
    private func preloadModel() async {
        logger.info("Preloading MLX model...")
        do {
            try await MLXWorker.shared.loadModel()
        } catch {
            logger.warning("Model preload failed: \(error.localizedDescription)")
        }
    }
    
    private func setupFolderMonitor() {
        folderMonitor = FolderMonitor(url: FolderMonitor.defaultDownloadsURL)
        folderMonitor?.onFolderDidChange = { [weak self] in
            self?.handleFolderChange()
        }
    }
    
    private func setupFileProcessor() {
        FileProcessor.shared.onActivityLogged = { [weak self] log in
            Task { @MainActor in
                self?.handleActivityLog(log)
            }
        }
    }
    
    private func setupReviewTrayTimer() {
        // Refresh review tray count every 5 seconds
        reviewTrayTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.refreshReviewTrayCount()
            }
        }
    }
    
    /// Refreshes the review tray file count
    func refreshReviewTrayCount() {
        reviewTrayCount = ClerkFileManager.shared.reviewTrayCount()
    }
    
    /// Updates FileProcessor with current rules and settings
    private func syncRulesToProcessor() {
        FileProcessor.shared.activeRules = rules.filter { $0.isEnabled }
        FileProcessor.shared.waitForModel = waitForModel
        FileProcessor.shared.aiEnabled = aiEnabled
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        do {
            let loadedRules = try await StorageService.shared.loadRules()
            rules = loadedRules.sorted { $0.priority < $1.priority }
            recentLogs = try await StorageService.shared.loadLogs()
            syncRulesToProcessor()
            logger.info("Loaded \(self.rules.count) rules and \(self.recentLogs.count) logs")
        } catch {
            logger.error("Failed to load data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        syncRulesToProcessor()
        folderMonitor?.start()
        isMonitoring = true
        logger.info("Monitoring started")
        
        // Immediately scan existing files in Downloads
        FileProcessor.shared.scanDownloadsFolder()
    }
    
    func stopMonitoring() {
        folderMonitor?.stop()
        isMonitoring = false
        logger.info("Monitoring stopped")
    }
    
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    // MARK: - Event Handling
    
    private func handleFolderChange() {
        lastChangeDetected = Date()
        logger.info("🔔 Folder change detected at \(self.lastChangeDetected?.description ?? "unknown")")
        
        // Trigger file processing pipeline
        FileProcessor.shared.scanDownloadsFolder()
        
        // Refresh review tray count after a short delay
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.refreshReviewTrayCount()
        }
    }
    
    private func handleActivityLog(_ log: ActivityLog) {
        // Add to recent logs (keep last 50)
        recentLogs.append(log)
        if recentLogs.count > 50 {
            recentLogs.removeFirst(recentLogs.count - 50)
        }
        
        // Persist to storage
        Task {
            try? await StorageService.shared.appendLog(log)
        }
        
        // Refresh review tray count
        refreshReviewTrayCount()
        
        logger.info("Activity: \(log.action.rawValue) - \(log.fileName)")
    }
    
    /// Manually trigger a scan of the Downloads folder
    func manualScan() {
        syncRulesToProcessor()
        FileProcessor.shared.scanDownloadsFolder()
    }
    
    // MARK: - Rules Management
    
    func addRule(prompt: String, targetPath: String) async {
        let rule = Rule(naturalPrompt: prompt, targetPath: targetPath)
        do {
            rules = try await StorageService.shared.addRule(rule)
            syncRulesToProcessor()
        } catch {
            logger.error("Failed to add rule: \(error.localizedDescription)")
        }
    }
    
    func updateRule(_ rule: Rule, prompt: String, targetPath: String) async {
        var updatedRule = rule
        updatedRule.naturalPrompt = prompt
        updatedRule.targetPath = targetPath
        do {
            rules = try await StorageService.shared.updateRule(updatedRule)
            syncRulesToProcessor()
        } catch {
            logger.error("Failed to update rule: \(error.localizedDescription)")
        }
    }
    
    func deleteRule(_ rule: Rule) async {
        do {
            rules = try await StorageService.shared.deleteRule(id: rule.id)
            syncRulesToProcessor()
        } catch {
            logger.error("Failed to delete rule: \(error.localizedDescription)")
        }
    }
    
    /// Reorders rules by moving from one index to another (for drag & drop)
    func reorderRules(fromOffsets: IndexSet, toOffset: Int) async {
        do {
            rules = try await StorageService.shared.reorderRules(fromOffsets: fromOffsets, toOffset: toOffset)
            syncRulesToProcessor()
            logger.info("Rules reordered successfully")
        } catch {
            logger.error("Failed to reorder rules: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Review Tray
    
    /// Opens the Review Tray folder in Finder
    func openReviewTray() {
        ClerkFileManager.shared.openReviewTray()
        // Refresh count after opening (user might delete files)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.refreshReviewTrayCount()
        }
    }
    
    // MARK: - Undo
    
    /// Returns the last undoable action, if any
    var lastUndoableAction: ActivityLog? {
        recentLogs.reversed().first { $0.canUndo }
    }
    
    /// Undoes the last file move action
    func undoLastMove() {
        guard let lastAction = lastUndoableAction,
              let sourcePath = lastAction.sourcePath,
              let destinationPath = lastAction.destinationPath else {
            logger.warning("No undoable action found")
            return
        }
        
        let fileManager = FileManager.default
        let destinationURL = URL(fileURLWithPath: destinationPath)
        
        // Check if file still exists at destination
        guard fileManager.fileExists(atPath: destinationPath) else {
            logger.warning("Cannot undo: file no longer exists at \(destinationPath)")
            return
        }
        
        // Build the REAL user Downloads path manually
        // FileManager.urls(for: .downloadsDirectory) returns sandbox path, not real path
        // We use /Users/<username>/Downloads directly
        let fileName = URL(fileURLWithPath: sourcePath).lastPathComponent
        let realDownloadsPath: String
        
        if sourcePath.contains("/Downloads/") {
            // Extract the real user path from the original source path
            // sourcePath should be like "/Users/juanleo/Downloads/file.txt"
            if let range = sourcePath.range(of: "/Downloads/") {
                let userPath = String(sourcePath[..<range.lowerBound])
                realDownloadsPath = userPath + "/Downloads/" + fileName
            } else {
                // Fallback: construct from username
                let username = NSUserName()
                realDownloadsPath = "/Users/\(username)/Downloads/\(fileName)"
            }
        } else {
            // Not Downloads, use original path
            realDownloadsPath = sourcePath
        }
        
        let realSourceURL = URL(fileURLWithPath: realDownloadsPath)
        
        logger.info("Attempting undo: \(destinationPath) -> \(realDownloadsPath)")
        
        Task { [weak self] in
            guard let self = self else { return }
            
            // Use shell command directly since we're dealing with paths outside sandbox
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/mv")
            process.arguments = [destinationPath, realDownloadsPath]
            
            let pipe = Pipe()
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    await MainActor.run {
                        self.logger.info("✅ Undo successful: moved \(lastAction.fileName) back to Downloads")
                        self.recentLogs.removeAll { $0.id == lastAction.id }
                        self.refreshReviewTrayCount()
                    }
                    
                    NotificationService.shared.notifyFileMoved(
                        fileName: lastAction.fileName,
                        destinationFolder: "Downloads (Undo)"
                    )
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    await MainActor.run {
                        self.logger.error("mv failed: \(errorMessage)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Undo failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
