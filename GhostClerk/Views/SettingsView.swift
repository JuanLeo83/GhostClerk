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
                        TextField("Target folder path", text: $newTargetPath)
                            .textFieldStyle(.roundedBorder)
                        
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
                    List {
                        ForEach(appState.rules) { rule in
                            RuleRowView(rule: rule, onDelete: {
                                Task {
                                    await appState.deleteRule(rule)
                                }
                            })
                        }
                    }
                    .listStyle(.inset)
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
            }
        }
    }
}

// MARK: - Rule Row View

struct RuleRowView: View {
    let rule: Rule
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.naturalPrompt)
                    .font(.body)
                
                Text("→ \(rule.targetPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
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

// MARK: - General Settings

struct GeneralSettingsView: View {
    
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showNotifications") private var showNotifications = true
    
    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Toggle("Show Notifications", isOn: $showNotifications)
            
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
