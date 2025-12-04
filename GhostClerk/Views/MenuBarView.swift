//
//  MenuBarView.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import SwiftUI

/// The main menu that appears when clicking the menu bar icon
struct MenuBarView: View {
    
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Alert Banner (if any)
            if let alert = currentAlert {
                alertBanner(alert)
                Divider()
            }
            
            // Quick Actions (most important - always at top)
            actionSection
            
            Divider()
            
            // Status Info
            statusSection
            
            Divider()
            
            // Recent Activity
            recentActivitySection
        }
        .frame(width: 320)
    }
    
    // MARK: - Alert Type
    
    private enum AlertType {
        case reviewTrayHasFiles(Int)
        case noRulesConfigured
        case monitoringPaused
        
        var icon: String {
            switch self {
            case .reviewTrayHasFiles: return "tray.full.fill"
            case .noRulesConfigured: return "exclamationmark.triangle.fill"
            case .monitoringPaused: return "pause.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .reviewTrayHasFiles: return .orange
            case .noRulesConfigured: return .yellow
            case .monitoringPaused: return .blue
            }
        }
        
        var title: String {
            switch self {
            case .reviewTrayHasFiles(let count):
                return count == 1 ? "1 file needs review" : "\(count) files need review"
            case .noRulesConfigured:
                return "No rules configured"
            case .monitoringPaused:
                return "Monitoring is paused"
            }
        }
        
        var subtitle: String {
            switch self {
            case .reviewTrayHasFiles:
                return "Click Review Tray to classify them"
            case .noRulesConfigured:
                return "Add rules in Settings to organize files"
            case .monitoringPaused:
                return "Click Start Monitoring to begin"
            }
        }
    }
    
    /// Determines the current alert to show (priority order)
    private var currentAlert: AlertType? {
        if appState.reviewTrayCount > 0 {
            return .reviewTrayHasFiles(appState.reviewTrayCount)
        }
        if appState.rules.isEmpty && appState.isMonitoring {
            return .noRulesConfigured
        }
        if !appState.isMonitoring {
            return .monitoringPaused
        }
        return nil
    }
    
    // MARK: - Alert Banner
    
    private func alertBanner(_ alert: AlertType) -> some View {
        HStack(spacing: 10) {
            Image(systemName: alert.icon)
                .foregroundColor(.white)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(alert.subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(alert.color)
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isMonitoring ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(appState.isMonitoring ? "Monitoring Active" : "Monitoring Paused")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            Text("Watching: ~/Downloads")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
            
            // Model loading status - inline
            modelStatusView
                .padding(.top, 2)
            
            Group {
                if let lastChange = appState.lastChangeDetected {
                    Text("Last change: \(lastChange.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Last change: None yet")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    /// Shows the current model loading state - all inline
    @ViewBuilder
    private var modelStatusView: some View {
        switch appState.modelLoadingState {
        case .idle:
            EmptyView()
        case .loading(let progress):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .loaded:
            Label("AI Ready", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let error):
            Label("AI: \(error.prefix(20))...", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
    
    // MARK: - Action Section
    
    private var actionSection: some View {
        VStack(spacing: 0) {
            // Primary actions
            Button {
                appState.toggleMonitoring()
            } label: {
                Label(
                    appState.isMonitoring ? "Pause Monitoring" : "Start Monitoring",
                    systemImage: appState.isMonitoring ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(MenuButtonStyle())
            
            Button {
                appState.manualScan()
            } label: {
                Label("Scan Now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(MenuButtonStyle())
            
            Button {
                appState.openReviewTray()
            } label: {
                HStack {
                    Label("Review Tray", systemImage: "tray.full")
                    Spacer()
                    if appState.reviewTrayCount > 0 {
                        Text("\(appState.reviewTrayCount)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(MenuButtonStyle())
            
            // Undo button (only if there's an undoable action)
            if let lastAction = appState.lastUndoableAction {
                Button {
                    appState.undoLastMove()
                } label: {
                    HStack {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                        Spacer()
                        Text(lastAction.fileName.count > 12 ? String(lastAction.fileName.prefix(12)) + "..." : lastAction.fileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("⌘Z")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(MenuButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
            }
            
            Divider()
            
            // Settings & Quit
            Button {
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings...", systemImage: "gear")
            }
            .buttonStyle(MenuButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Ghost Clerk", systemImage: "power")
            }
            .buttonStyle(MenuButtonStyle())
            .keyboardShortcut("q", modifiers: .command)
        }
    }
    
    // MARK: - Recent Activity Section
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent Activity")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            
            if appState.recentLogs.isEmpty {
                Text("No recent activity")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(appState.recentLogs.suffix(5).reversed()) { log in
                    Text("\(iconEmojiForAction(log.action)) \(truncateFileName(log.fileName, maxLength: 22)) · \(shortTimeAgo(log.timestamp))")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Helpers
    
    private func iconForAction(_ action: ActionType) -> String {
        switch action {
        case .scanned: return "doc.viewfinder"
        case .moved: return "folder.fill"
        case .renamed: return "pencil"
        case .deleted: return "trash"
        case .whitelisted: return "checkmark.shield"
        case .reviewTray: return "tray"
        case .skipped: return "forward.fill"
        }
    }
    
    private func colorForStatus(_ status: ActionStatus) -> Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .pending: return .orange
        case .retrying: return .yellow
        }
    }
    
    private func iconEmojiForAction(_ action: ActionType) -> String {
        switch action {
        case .scanned: return "🔍"
        case .moved: return "📁"
        case .renamed: return "✏️"
        case .deleted: return "🗑️"
        case .whitelisted: return "✅"
        case .reviewTray: return "📥"
        case .skipped: return "⏭️"
        }
    }
    
    private func truncateFileName(_ name: String, maxLength: Int) -> String {
        guard name.count > maxLength else { return name }
        let ext = (name as NSString).pathExtension
        let nameWithoutExt = (name as NSString).deletingPathExtension
        let availableLength = maxLength - ext.count - 4 // 4 for "..." and "."
        if availableLength > 0 && nameWithoutExt.count > availableLength {
            let truncated = String(nameWithoutExt.prefix(availableLength))
            return ext.isEmpty ? "\(truncated)..." : "\(truncated)...\(ext)"
        }
        return String(name.prefix(maxLength - 3)) + "..."
    }
    
    private func shortTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

// MARK: - Menu Button Style

struct MenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
