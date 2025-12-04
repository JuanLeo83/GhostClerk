//
//  MLXWorker.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import os.log
import MLXLLM
import MLXLMCommon

/// Model loading state for UI updates
enum ModelLoadingState: Equatable {
    case idle
    case loading(progress: String)
    case loaded
    case failed(error: String)
    
    var isReady: Bool {
        if case .loaded = self { return true }
        return false
    }
}

/// Service responsible for running local LLM inference using MLX.
/// Uses a small, quantized model optimized for Apple Silicon.
actor MLXWorker {
    
    // MARK: - Singleton
    
    static let shared = MLXWorker()
    
    // MARK: - Available Models
    
    /// Available models for selection
    static let availableModels: [MLXModel] = [
        MLXModel(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            name: "Phi-3.5 Mini",
            size: "~2 GB",
            shortDescription: "Recommended",
            description: "Best balance of speed and accuracy"
        ),
        MLXModel(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            name: "Llama 3.2 1B",
            size: "~0.7 GB",
            shortDescription: "Fastest",
            description: "Lightest model, ideal for simple rules"
        ),
        MLXModel(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            name: "Llama 3.2 3B",
            size: "~2 GB",
            shortDescription: "Better reasoning",
            description: "More capable than 1B variant"
        ),
        MLXModel(
            id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            name: "Qwen 2.5 3B",
            size: "~2 GB",
            shortDescription: "Best multilingual",
            description: "Excellent support for Spanish and other languages"
        )
    ]
    
    /// Default model ID
    static let defaultModelId = "mlx-community/Phi-3.5-mini-instruct-4bit"
    
    // MARK: - Configuration
    
    /// Currently selected model ID (persisted)
    private var modelId: String {
        UserDefaults.standard.string(forKey: "selectedModelId") ?? Self.defaultModelId
    }
    
    /// Gets the currently selected model info
    var currentModel: MLXModel? {
        Self.availableModels.first { $0.id == modelId }
    }
    
    /// Changes the selected model (requires reload)
    func selectModel(_ id: String) {
        UserDefaults.standard.set(id, forKey: "selectedModelId")
        // Unload current model - will load new one on next inference
        unloadModel()
        logger.info("Model changed to: \(id)")
    }
    
    // MARK: - Downloaded Models Tracking
    
    /// Key for storing downloaded model IDs
    private static let downloadedModelsKey = "downloadedModelIds"
    
    /// Gets the set of downloaded model IDs
    static var downloadedModelIds: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: downloadedModelsKey) ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: downloadedModelsKey)
        }
    }
    
    /// Syncs downloaded models tracking with actual files on disk
    /// Call this on app launch or when Settings opens to ensure consistency
    static func syncDownloadedModelsWithDisk() -> Set<String> {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return []
        }
        
        let modelsDir = cacheDir
            .appendingPathComponent("models")
            .appendingPathComponent("mlx-community")
        
        guard FileManager.default.fileExists(atPath: modelsDir.path) else {
            downloadedModelIds = []
            return []
        }
        
        var actuallyDownloaded = Set<String>()
        
        // Check each known model
        for model in availableModels {
            let modelFolderName = model.id.components(separatedBy: "/").last ?? model.id
            let modelPath = modelsDir.appendingPathComponent(modelFolderName)
            
            if FileManager.default.fileExists(atPath: modelPath.path) {
                actuallyDownloaded.insert(model.id)
            }
        }
        
        // Update the stored set to match reality
        downloadedModelIds = actuallyDownloaded
        
        return actuallyDownloaded
    }
    
    /// Marks a model as downloaded
    func markModelAsDownloaded(_ modelId: String) {
        var downloaded = Self.downloadedModelIds
        downloaded.insert(modelId)
        Self.downloadedModelIds = downloaded
        logger.info("Marked model as downloaded: \(modelId)")
    }
    
    /// Checks if a model is downloaded
    static func isModelDownloaded(_ modelId: String) -> Bool {
        downloadedModelIds.contains(modelId)
    }
    
    /// Deletes a specific model's cache (not the currently selected one)
    func deleteModelCache(for modelIdToDelete: String) throws {
        // Safety check: don't delete the currently selected/loaded model
        if modelIdToDelete == modelId {
            throw MLXError.cannotDeleteActiveModel
        }
        
        // Get the model folder name from the ID (e.g., "mlx-community/Phi-3.5-mini-instruct-4bit" -> "Phi-3.5-mini-instruct-4bit")
        let modelFolderName = modelIdToDelete.components(separatedBy: "/").last ?? modelIdToDelete
        
        // Find and delete the model folder
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw MLXError.modelDeleteFailed("Cannot access cache directory")
        }
        
        // Model is stored in: ~/Library/Caches/models/mlx-community/<model-name>/
        let modelPath = cacheDir
            .appendingPathComponent("models")
            .appendingPathComponent("mlx-community")
            .appendingPathComponent(modelFolderName)
        
        if FileManager.default.fileExists(atPath: modelPath.path) {
            // Calculate size before deletion for logging
            let size = Self.directorySize(at: modelPath)
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: size)
            
            try FileManager.default.removeItem(at: modelPath)
            logger.info("✅ Deleted model \(modelFolderName) - freed \(sizeString)")
        } else {
            logger.warning("Model folder not found at: \(modelPath.path)")
        }
        
        // Remove from downloaded set
        var downloaded = Self.downloadedModelIds
        downloaded.remove(modelIdToDelete)
        Self.downloadedModelIds = downloaded
    }
    
    /// Gets the actual size of a specific model on disk
    func getModelDiskSize(for modelIdToCheck: String) -> Int64 {
        let modelFolderName = modelIdToCheck.components(separatedBy: "/").last ?? modelIdToCheck
        
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        
        let modelPath = cacheDir
            .appendingPathComponent("models")
            .appendingPathComponent("mlx-community")
            .appendingPathComponent(modelFolderName)
        
        return Self.directorySize(at: modelPath)
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.juanleodev.GhostClerk", category: "MLXWorker")
    
    /// Callback to notify state changes (for UI updates)
    private var onStateChangeCallback: ((ModelLoadingState) -> Void)?
    
    /// Sets the callback for state changes (called from MainActor)
    func setStateCallback(_ callback: @escaping (ModelLoadingState) -> Void) {
        onStateChangeCallback = callback
        // Immediately notify current state
        callback(loadingState)
    }
    
    /// Current loading state
    private(set) var loadingState: ModelLoadingState = .idle {
        didSet {
            let state = loadingState
            let callback = onStateChangeCallback
            Task { @MainActor in
                callback?(state)
            }
        }
    }
    
    /// Whether the model is currently loaded
    private(set) var isModelLoaded = false
    
    /// Whether model is currently loading
    private(set) var isLoading = false
    
    /// The loaded model context
    private var modelContext: ModelContext?
    
    /// Chat session for conversational inference
    private var chatSession: ChatSession?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Loads the LLM model into memory.
    /// This may take a while on first run as it downloads the model (~2GB).
    func loadModel() async throws {
        guard !isModelLoaded && !isLoading else {
            logger.debug("Model already loaded or loading")
            return
        }
        
        isLoading = true
        loadingState = .loading(progress: "Downloading model...")
        defer { isLoading = false }
        
        logger.info("Loading MLX model: \(self.modelId)")
        
        do {
            loadingState = .loading(progress: "Loading \(modelId.components(separatedBy: "/").last ?? "model")...")
            
            // Load the model from Hugging Face using the simplified API
            let loadedModel = try await MLXLMCommon.loadModel(id: modelId)
            
            // Store the model context
            modelContext = loadedModel
            
            // Create a chat session
            chatSession = ChatSession(loadedModel)
            
            isModelLoaded = true
            loadingState = .loaded
            
            // Mark this model as downloaded
            markModelAsDownloaded(modelId)
            
            logger.info("✅ Model loaded successfully: \(self.modelId)")
        } catch {
            loadingState = .failed(error: error.localizedDescription)
            logger.error("❌ Failed to load model: \(error.localizedDescription)")
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
    }
    
    /// Unloads the model from memory to free resources.
    func unloadModel() {
        modelContext = nil
        chatSession = nil
        isModelLoaded = false
        loadingState = .idle
        logger.info("Model unloaded")
    }
    
    /// Returns the size of the cached model on disk (if any)
    func getModelCacheSize() -> Int64 {
        // MLX stores models in the app's Caches directory (sandbox container)
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        
        // Check multiple possible locations
        let possiblePaths = [
            cacheDir.appendingPathComponent("huggingface/hub"),  // Standard HF location
            cacheDir.appendingPathComponent("models"),           // MLX Swift location
            cacheDir                                              // Entire cache dir as fallback
        ]
        
        for path in possiblePaths {
            let size = Self.directorySize(at: path)
            if size > 0 {
                logger.debug("Found cache at \(path.path): \(size) bytes")
                return size
            }
        }
        
        return 0
    }
    
    /// Deletes the downloaded model from disk cache
    func deleteModelCache() throws {
        // First unload from memory
        unloadModel()
        
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        
        // Delete both possible cache locations
        let pathsToDelete = [
            cacheDir.appendingPathComponent("huggingface"),
            cacheDir.appendingPathComponent("models")
        ]
        
        for path in pathsToDelete {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
                logger.info("Deleted model cache at: \(path.path)")
            }
        }
    }
    
    /// Calculates total size of a directory
    private static func directorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
    
    /// Waits for the model to finish loading (with timeout).
    /// Returns true if model loaded successfully, false otherwise.
    func waitForModelReady(timeout: TimeInterval = 120) async -> Bool {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            if isModelLoaded {
                return true
            }
            if case .failed = loadingState {
                return false
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        
        logger.warning("Model loading timed out after \(timeout)s")
        return false
    }
    
    /// Performs inference to match file content against rules.
    /// - Parameters:
    ///   - text: Extracted text from the file (includes filename and content)
    ///   - rules: Array of user rules in priority order
    /// - Returns: The matched Rule, or nil if no rule matches
    func infer(text: String, rules: [Rule]) async throws -> Rule? {
        guard !rules.isEmpty else {
            logger.debug("No rules provided for inference")
            return nil
        }
        
        // Try to load model if not loaded
        if !isModelLoaded {
            logger.info("Model not loaded, loading now...")
            do {
                try await loadModel()
            } catch {
                logger.warning("Failed to load model, using keyword fallback: \(error.localizedDescription)")
                return mockInference(text: text, rules: rules)
            }
        }
        
        guard let session = chatSession else {
            logger.warning("Chat session not initialized, using keyword fallback")
            return mockInference(text: text, rules: rules)
        }
        
        // Build the prompt
        let prompt = PromptBuilder.buildPrompt(
            rules: rules,
            fileName: "",
            extractedText: text
        )
        
        logger.debug("Running inference with \(rules.count) rules")
        
        do {
            // Run inference
            let response = try await session.respond(to: prompt)
            
            logger.debug("LLM response: \(response)")
            
            // Parse the response to get rule index
            if let ruleIndex = PromptBuilder.parseResponse(response, rulesCount: rules.count) {
                let matchedRule = rules[ruleIndex]
                logger.info("✅ Matched rule \(ruleIndex + 1): '\(matchedRule.naturalPrompt)'")
                return matchedRule
            }
            
            logger.info("No rule matched by LLM")
            return nil
            
        } catch {
            logger.error("Inference failed: \(error.localizedDescription)")
            
            // Fallback to mock inference if LLM fails
            logger.warning("Falling back to keyword matching")
            return mockInference(text: text, rules: rules)
        }
    }
    
    // MARK: - Fallback Mock Implementation
    
    /// Mock inference that uses simple keyword matching.
    /// Used as fallback when LLM inference fails.
    private func mockInference(text: String, rules: [Rule]) -> Rule? {
        let lowercasedText = text.lowercased()
        
        logger.debug("Mock inference analyzing text")
        
        // Try each rule in priority order
        for rule in rules {
            let keywords = extractKeywords(from: rule.naturalPrompt)
            
            // Check each keyword
            var matchedKeywords: [String] = []
            for keyword in keywords {
                if lowercasedText.contains(keyword) {
                    matchedKeywords.append(keyword)
                }
            }
            
            // Match if at least one keyword found
            if !matchedKeywords.isEmpty {
                logger.info("Mock matched rule: '\(rule.naturalPrompt)' with keywords: \(matchedKeywords)")
                return rule
            }
        }
        
        logger.debug("Mock inference: no rule matched")
        return nil
    }
    
    /// Extracts simple keywords from a rule prompt for mock matching.
    private func extractKeywords(from prompt: String) -> [String] {
        let stopWords = Set([
            "the", "a", "an", "and", "or", "to", "for", "of", "in", "on", "at",
            "is", "are", "that", "this", "with", "files", "file", "move", "put",
            "all", "any", "my", "into", "folder", "should", "go", "be", "como",
            "los", "las", "que", "con", "por", "para", "del", "una", "uno"
        ])
        
        return prompt
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }
    
    // MARK: - Errors
    
    enum MLXError: LocalizedError {
        case modelLoadFailed(String)
        case sessionNotInitialized
        case inferenceFailed(String)
        case cannotDeleteActiveModel
        case modelDeleteFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let reason):
                return "Failed to load MLX model: \(reason)"
            case .sessionNotInitialized:
                return "Chat session not initialized"
            case .inferenceFailed(let reason):
                return "Inference failed: \(reason)"
            case .cannotDeleteActiveModel:
                return "Cannot delete the currently active model"
            case .modelDeleteFailed(let reason):
                return "Failed to delete model: \(reason)"
            }
        }
    }
}

// MARK: - Model Info

/// Represents an available MLX model
struct MLXModel: Identifiable, Equatable {
    let id: String
    let name: String
    let size: String
    let shortDescription: String
    let description: String
    
    /// Formatted display name for picker: "Phi-3.5 Mini (~2 GB) - Recomendado"
    var displayName: String {
        "\(name) (\(size)) - \(shortDescription)"
    }
}
