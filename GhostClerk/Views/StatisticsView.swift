//
//  StatisticsView.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import SwiftUI
import Charts

/// Statistics Dashboard showing file processing metrics
struct StatisticsView: View {
    
    @EnvironmentObject var appState: AppState
    @State private var allLogs: [ActivityLog] = []
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Cards
                summarySection
                
                // Action Distribution Chart
                actionDistributionSection
                
                // Files by Rule
                filesByRuleSection
                
                // Recent Activity Timeline
                recentActivitySection
            }
            .padding()
        }
        .task {
            await loadAllLogs()
        }
    }
    
    // MARK: - Summary Section
    
    private var summarySection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: "Total Processed",
                value: "\(totalProcessed)",
                icon: "doc.fill",
                color: .blue
            )
            
            StatCard(
                title: "Moved",
                value: "\(movedCount)",
                icon: "folder.fill",
                color: .green
            )
            
            StatCard(
                title: "Review Tray",
                value: "\(reviewTrayCount)",
                icon: "tray.fill",
                color: .orange
            )
            
            StatCard(
                title: "Duplicates",
                value: "\(duplicatesCount)",
                icon: "doc.on.doc.fill",
                color: .purple
            )
        }
    }
    
    // MARK: - Action Distribution
    
    private var actionDistributionSection: some View {
        GroupBox("Action Distribution") {
            if actionStats.isEmpty {
                Text("No data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                Chart(actionStats, id: \.action) { stat in
                    BarMark(
                        x: .value("Count", stat.count),
                        y: .value("Action", stat.action.displayName)
                    )
                    .foregroundStyle(stat.action.color)
                    .annotation(position: .trailing) {
                        Text("\(stat.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: CGFloat(actionStats.count * 35 + 20))
                .padding()
            }
        }
    }
    
    // MARK: - Files by Rule
    
    private var filesByRuleSection: some View {
        GroupBox("Files by Rule") {
            if filesByRule.isEmpty {
                Text("No files matched rules yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filesByRule.prefix(5), id: \.ruleId) { stat in
                        HStack {
                            Circle()
                                .fill(ruleColor(for: stat.ruleId))
                                .frame(width: 8, height: 8)
                            
                            Text(ruleName(for: stat.ruleId))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(stat.count) files")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Recent Activity
    
    private var recentActivitySection: some View {
        GroupBox("Recent Activity") {
            if recentLogs.isEmpty {
                Text("No recent activity")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recentLogs) { log in
                        HStack(spacing: 8) {
                            Image(systemName: log.action.icon)
                                .foregroundColor(log.action.color)
                                .frame(width: 16)
                            
                            Text(log.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Text(log.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var totalProcessed: Int {
        allLogs.filter { $0.status == .success && $0.action != .scanned }.count
    }
    
    private var movedCount: Int {
        allLogs.filter { $0.action == .moved && $0.status == .success }.count
    }
    
    private var reviewTrayCount: Int {
        allLogs.filter { $0.action == .reviewTray && $0.status == .success }.count
    }
    
    private var duplicatesCount: Int {
        allLogs.filter { ($0.action == .deleted || $0.action == .renamed) && $0.status == .success }.count
    }
    
    private var actionStats: [ActionStat] {
        let grouped = Dictionary(grouping: allLogs.filter { $0.status == .success && $0.action != .scanned }) { $0.action }
        return grouped.map { ActionStat(action: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    private var filesByRule: [RuleStat] {
        let logsWithRules = allLogs.filter { $0.matchedRuleId != nil && $0.status == .success }
        let grouped = Dictionary(grouping: logsWithRules) { $0.matchedRuleId! }
        return grouped.map { RuleStat(ruleId: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    private var recentLogs: [ActivityLog] {
        Array(allLogs.filter { $0.status == .success && $0.action != .scanned }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(10))
    }
    
    // MARK: - Helpers
    
    private func loadAllLogs() async {
        isLoading = true
        do {
            allLogs = try await StorageService.shared.loadLogs()
        } catch {
            allLogs = []
        }
        isLoading = false
    }
    
    private func ruleName(for id: UUID) -> String {
        appState.rules.first { $0.id == id }?.naturalPrompt ?? "Unknown Rule"
    }
    
    private func ruleColor(for id: UUID) -> Color {
        let index = appState.rules.firstIndex { $0.id == id } ?? 0
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint]
        return colors[index % colors.count]
    }
}

// MARK: - Supporting Types

private struct ActionStat {
    let action: ActionType
    let count: Int
}

private struct RuleStat {
    let ruleId: UUID
    let count: Int
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - ActionType Extensions

extension ActionType {
    var displayName: String {
        switch self {
        case .scanned: return "Scanned"
        case .moved: return "Moved"
        case .renamed: return "Renamed"
        case .deleted: return "Deleted (Duplicate)"
        case .whitelisted: return "Whitelisted"
        case .reviewTray: return "Review Tray"
        case .skipped: return "Skipped"
        }
    }
    
    var icon: String {
        switch self {
        case .scanned: return "doc.text.magnifyingglass"
        case .moved: return "folder.fill"
        case .renamed: return "pencil"
        case .deleted: return "trash.fill"
        case .whitelisted: return "checkmark.shield.fill"
        case .reviewTray: return "tray.fill"
        case .skipped: return "arrow.right.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .scanned: return .gray
        case .moved: return .green
        case .renamed: return .blue
        case .deleted: return .purple
        case .whitelisted: return .cyan
        case .reviewTray: return .orange
        case .skipped: return .secondary
        }
    }
}

#Preview {
    StatisticsView()
        .environmentObject(AppState())
        .frame(width: 500, height: 450)
}
