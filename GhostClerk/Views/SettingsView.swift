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
            
            StatisticsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.fill")
                }
            
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 550, height: 450)
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
    
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("waitForModel") private var waitForModel = true
    @AppStorage("aiEnabled") private var aiEnabled = true
    
    @State private var modelCacheSize: Int64 = 0
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var showPromptEditor = false
    @State private var customPrompt: String = ""
    @State private var isUsingCustomPrompt = false
    @AppStorage("retryWithLLM") private var retryWithLLM = true
    
    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Toggle("Show Notifications", isOn: $showNotifications)
            
            Section("AI Model") {
                Toggle("Enable AI Classification", isOn: $aiEnabled)
                Text("When disabled, files go to Review Tray. Saves GPU/memory resources.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if aiEnabled {
                    Toggle("Wait for model before classifying", isOn: $waitForModel)
                    Text("Files wait for AI to load instead of using keyword fallback.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !waitForModel {
                        Toggle("Retry with AI when model loads", isOn: $retryWithLLM)
                        Text("Re-classify files that used keyword fallback once AI is ready.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Model status
                HStack {
                    Text("Status:")
                    Spacer()
                    modelStatusText
                }
                
                // Cache size
                HStack {
                    Text("Cache Size:")
                    Spacer()
                    Text(formatBytes(modelCacheSize))
                        .foregroundColor(.secondary)
                }
                
                // Delete model button
                if modelCacheSize > 0 {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(isDeleting ? "Deleting..." : "Delete Downloaded Model")
                        }
                    }
                    .disabled(isDeleting)
                }
            }
            
            Section("Prompt Tuning") {
                HStack {
                    Text("System Prompt:")
                    Spacer()
                    if isUsingCustomPrompt {
                        Text("Custom")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    } else {
                        Text("Default")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Edit System Prompt...") {
                    customPrompt = PromptBuilder.systemPrompt
                    showPromptEditor = true
                }
                
                if isUsingCustomPrompt {
                    Button("Reset to Default") {
                        PromptBuilder.resetToDefault()
                        isUsingCustomPrompt = false
                    }
                }
                
                Text("The system prompt tells the AI how to classify files.")
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
        .onAppear {
            refreshCacheSize()
            isUsingCustomPrompt = PromptBuilder.isUsingCustomPrompt
        }
        .sheet(isPresented: $showPromptEditor) {
            PromptEditorSheet(
                prompt: $customPrompt,
                isPresented: $showPromptEditor,
                onSave: {
                    PromptBuilder.setCustomPrompt(customPrompt)
                    isUsingCustomPrompt = PromptBuilder.isUsingCustomPrompt
                }
            )
        }
        .confirmationDialog(
            "Delete Model Cache?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteModelCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the downloaded AI model (\(formatBytes(modelCacheSize))). You'll need to re-download it when AI is used again.")
        }
    }
    
    @ViewBuilder
    private var modelStatusText: some View {
        switch appState.modelLoadingState {
        case .idle:
            Text("Not loaded")
                .foregroundColor(.secondary)
        case .loading(let progress):
            Text(progress)
                .foregroundColor(.orange)
        case .loaded:
            Text("Ready")
                .foregroundColor(.green)
        case .failed(let error):
            Text("Error: \(error.prefix(20))...")
                .foregroundColor(.red)
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func refreshCacheSize() {
        Task {
            let size = await MLXWorker.shared.getModelCacheSize()
            await MainActor.run {
                modelCacheSize = size
            }
        }
    }
    
    private func deleteModelCache() {
        isDeleting = true
        Task {
            do {
                try await MLXWorker.shared.deleteModelCache()
                await MainActor.run {
                    modelCacheSize = 0
                    isDeleting = false
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }
}

// MARK: - Prompt Editor Sheet

struct PromptEditorSheet: View {
    @Binding var prompt: String
    @Binding var isPresented: Bool
    var onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit System Prompt")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
            }
            
            Text("This prompt tells the AI how to analyze and classify files. Modify carefully.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextEditor(text: $prompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color(nsColor: .separatorColor), width: 1)
            
            HStack {
                Button("Reset to Default") {
                    prompt = PromptBuilder.defaultSystemPrompt
                }
                
                Spacer()
                
                Button("Save") {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 350)
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
