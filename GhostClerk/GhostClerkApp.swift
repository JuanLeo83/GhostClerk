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
            // SF Symbol for the menu bar icon
            Image(systemName: appState.isMonitoring ? "eye.fill" : "eye.slash")
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
    
    /// The folder monitor instance
    private var folderMonitor: FolderMonitor?
    
    init() {
        setupFolderMonitor()
        setupFileProcessor()
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
    
    /// Number of files in the Review Tray
    var reviewTrayCount: Int {
        ClerkFileManager.shared.reviewTrayCount()
    }
    
    /// Opens the Review Tray folder in Finder
    func openReviewTray() {
        ClerkFileManager.shared.openReviewTray()
    }
}
