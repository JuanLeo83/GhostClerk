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
    
    /// The folder monitor instance
    private var folderMonitor: FolderMonitor?
    
    /// Timer to periodically refresh review tray count
    private var reviewTrayTimer: Timer?
    
    init() {
        setupFolderMonitor()
        setupFileProcessor()
        setupReviewTrayTimer()
        refreshReviewTrayCount()
        Task {
            await loadData()
        }
    }
    
    // MARK: - Setup
    
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
            Task { @MainActor in
                self?.refreshReviewTrayCount()
            }
        }
    }
    
    /// Refreshes the review tray file count
    func refreshReviewTrayCount() {
        reviewTrayCount = ClerkFileManager.shared.reviewTrayCount()
    }
    
    /// Updates FileProcessor with current rules
    private func syncRulesToProcessor() {
        FileProcessor.shared.activeRules = rules.filter { $0.isEnabled }
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        do {
            rules = try await StorageService.shared.loadRules()
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
}
