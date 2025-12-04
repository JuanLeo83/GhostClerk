//
//  SettingsView.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import SwiftUI
import UniformTypeIdentifiers

/// The Settings window for managing rules and preferences
struct SettingsView: View {
    
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView {
            RulesSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Rules", systemImage: "list.bullet.rectangle")
                }
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Rules Settings

struct RulesSettingsView: View {
    
    @EnvironmentObject var appState: AppState
    @State private var newPrompt = ""
    @State private var newTargetPath = ""
    @State private var showingFolderPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Add new rule section
            GroupBox("Add New Rule") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Natural language rule (e.g., 'Move invoices to House')", text: $newPrompt)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack {
                        Text(newTargetPath.isEmpty ? "Select a folder..." : newTargetPath)
                            .foregroundColor(newTargetPath.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        
                        Button("Browse...") {
                            showingFolderPicker = true
                        }
                    }
                    
                    Button("Add Rule") {
                        guard !newPrompt.isEmpty, !newTargetPath.isEmpty else { return }
                        Task {
                            await appState.addRule(prompt: newPrompt, targetPath: newTargetPath)
                            newPrompt = ""
                            newTargetPath = ""
                        }
                    }
                    .disabled(newPrompt.isEmpty || newTargetPath.isEmpty)
                }
                .padding(8)
            }
            
            // Existing rules list
            GroupBox("Active Rules (\(appState.rules.count))") {
                if appState.rules.isEmpty {
                    Text("No rules configured yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Drag to reorder • Higher = more priority")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                        
                        List {
                            ForEach(Array(appState.rules.enumerated()), id: \.element.id) { index, rule in
                                RuleRowView(
                                    rule: rule,
                                    priorityNumber: index + 1,
                                    onEdit: { newPrompt, newTargetPath in
                                        Task {
                                            await appState.updateRule(rule, prompt: newPrompt, targetPath: newTargetPath)
                                        }
                                    },
                                    onDelete: {
                                        Task {
                                            await appState.deleteRule(rule)
                                        }
                                    }
                                )
                            }
                            .onMove { fromOffsets, toOffset in
                                Task {
                                    await appState.reorderRules(fromOffsets: fromOffsets, toOffset: toOffset)
                                }
                            }
                        }
                        .listStyle(.inset)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                newTargetPath = url.path
                // Save bookmark for persistent access
                Task {
                    try? await BookmarkManager.shared.saveBookmark(for: url)
                }
            }
        }
    }
}

// MARK: - Rule Row View

struct RuleRowView: View {
    let rule: Rule
    let priorityNumber: Int
    let onEdit: (String, String) -> Void
    let onDelete: () -> Void
    
    @State private var isEditing = false
    @State private var editPrompt: String = ""
    @State private var editTargetPath: String = ""
    @State private var showingFolderPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                // Edit mode
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Rule description", text: $editPrompt)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack {
                        Text(editTargetPath.isEmpty ? "Select a folder..." : editTargetPath)
                            .foregroundColor(editTargetPath.isEmpty ? .secondary : .primary)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        
                        Button("Browse") {
                            showingFolderPicker = true
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    HStack {
                        Button("Save") {
                            onEdit(editPrompt, editTargetPath)
                            isEditing = false
                        }
                        .disabled(editPrompt.isEmpty || editTargetPath.isEmpty)
                        
                        Button("Cancel") {
                            isEditing = false
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                // Display mode
                HStack(spacing: 12) {
                    // Priority badge
                    Text("\(priorityNumber)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.naturalPrompt)
                            .font(.body)
                        
                        Text("→ \(rule.targetPath)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        editPrompt = rule.naturalPrompt
                        editTargetPath = rule.targetPath
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                editTargetPath = url.path
                // Save bookmark for persistent access
                Task {
                    try? await BookmarkManager.shared.saveBookmark(for: url)
                }
            }
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("waitForModel") private var waitForModel = true
    
    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Toggle("Show Notifications", isOn: $showNotifications)
            
            Section("AI Model") {
                Toggle("Wait for model before classifying", isOn: $waitForModel)
                Text("When enabled, files wait for the AI model to load before being classified. This prevents fallback keyword matching during startup.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Watched Folder") {
                HStack {
                    Text("~/Downloads")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("(Default)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Ghost Clerk")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 0.1.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("AI-powered local file organizer")
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
