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
    
    // MARK: - Data Loading
    
    private func loadData() async {
        do {
            rules = try await StorageService.shared.loadRules()
            recentLogs = try await StorageService.shared.loadLogs()
            logger.info("Loaded \(self.rules.count) rules and \(self.recentLogs.count) logs")
        } catch {
            logger.error("Failed to load data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        folderMonitor?.start()
        isMonitoring = true
        logger.info("Monitoring started")
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
        
        // TODO: Phase 1 - Trigger file processing pipeline here
    }
    
    // MARK: - Rules Management
    
    func addRule(prompt: String, targetPath: String) async {
        let rule = Rule(naturalPrompt: prompt, targetPath: targetPath)
        do {
            rules = try await StorageService.shared.addRule(rule)
        } catch {
            logger.error("Failed to add rule: \(error.localizedDescription)")
        }
    }
    
    func deleteRule(_ rule: Rule) async {
        do {
            rules = try await StorageService.shared.deleteRule(id: rule.id)
        } catch {
            logger.error("Failed to delete rule: \(error.localizedDescription)")
        }
    }
}
