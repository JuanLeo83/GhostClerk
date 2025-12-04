//
//  MLXWorker.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import os.log

// Note: Import MLXLLM when the package is added to the project
// import MLXLLM
// import MLXLMCommon

/// Service responsible for running local LLM inference using MLX.
/// Uses a small, quantized model optimized for Apple Silicon.
actor MLXWorker {
    
    // MARK: - Singleton
    
    static let shared = MLXWorker()
    
    // MARK: - Configuration
    
    /// Model to use - Phi-3.5-mini is small (~2GB) and good for classification tasks
    /// Alternative: "mlx-community/Qwen3-4B-4bit" (~2.5GB)
    private let modelId = "mlx-community/Phi-3.5-mini-instruct-4bit"
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.juanleodev.GhostClerk", category: "MLXWorker")
    
    /// Whether the model is currently loaded
    private(set) var isModelLoaded = false
    
    /// Whether model is currently loading
    private(set) var isLoading = false
    
    /// Placeholder for the actual model - will be typed as LLMModel when MLXLLM is imported
    private var model: Any?
    
    /// Placeholder for chat session
    private var chatSession: Any?
    
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
        defer { isLoading = false }
        
        logger.info("Loading MLX model: \(self.modelId)")
        
        // TODO: Uncomment when MLXLLM package is added
        /*
        do {
            let loadedModel = try await MLXLLM.loadModel(id: modelId)
            self.model = loadedModel
            self.chatSession = ChatSession(loadedModel)
            isModelLoaded = true
            logger.info("Model loaded successfully")
        } catch {
            logger.error("Failed to load model: \(error.localizedDescription)")
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
        */
        
        // Temporary: Simulate loading for now
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        isModelLoaded = true
        logger.info("Model loaded (simulated)")
    }
    
    /// Unloads the model from memory to free resources.
    func unloadModel() {
        model = nil
        chatSession = nil
        isModelLoaded = false
        logger.info("Model unloaded")
    }
    
    /// Performs inference to match file content against rules.
    /// - Parameters:
    ///   - text: Extracted text from the file
    ///   - rules: Array of user rules in priority order
    /// - Returns: The matched Rule, or nil if no rule matches
    func infer(text: String, rules: [Rule]) async throws -> Rule? {
        guard !rules.isEmpty else {
            logger.debug("No rules provided for inference")
            return nil
        }
        
        if !isModelLoaded {
            logger.warning("Model not loaded, attempting to load...")
            try await loadModel()
        }
        
        // Build the prompt
        let prompt = PromptBuilder.buildPrompt(
            rules: rules,
            fileName: "", // We don't have filename here, it's embedded in the extracted text context
            extractedText: text
        )
        
        logger.debug("Running inference with \(rules.count) rules, prompt length: \(prompt.count)")
        
        // TODO: Uncomment when MLXLLM package is added
        /*
        guard let session = chatSession as? ChatSession else {
            throw MLXError.sessionNotInitialized
        }
        
        // Use system prompt for context
        let response = try await session.respond(
            to: prompt,
            systemPrompt: PromptBuilder.systemPrompt
        )
        
        // Parse the response to get rule index
        if let ruleIndex = PromptBuilder.parseResponse(response, rulesCount: rules.count) {
            let matchedRule = rules[ruleIndex]
            logger.info("Matched rule: \(matchedRule.naturalPrompt)")
            return matchedRule
        }
        
        logger.debug("No rule matched")
        return nil
        */
        
        // Temporary: Mock inference - randomly match or not
        // This allows testing the full pipeline without the actual model
        return mockInference(text: text, rules: rules)
    }
    
    // MARK: - Mock Implementation (for testing without MLX)
    
    /// Mock inference that uses simple keyword matching.
    /// Replace with real MLX inference when the package is integrated.
    private func mockInference(text: String, rules: [Rule]) -> Rule? {
        let lowercasedText = text.lowercased()
        
        logger.debug("Mock inference analyzing text (\(lowercasedText.prefix(100))...)")
        
        // Try each rule in priority order
        for rule in rules {
            let keywords = extractKeywords(from: rule.naturalPrompt)
            logger.debug("Rule '\(rule.naturalPrompt)' keywords: \(keywords)")
            
            // Check each keyword
            var matchedKeywords: [String] = []
            for keyword in keywords {
                if lowercasedText.contains(keyword) {
                    matchedKeywords.append(keyword)
                }
            }
            
            // Match if at least one keyword found (more lenient for testing)
            if !matchedKeywords.isEmpty {
                logger.info("Mock inference matched rule: '\(rule.naturalPrompt)' with keywords: \(matchedKeywords)")
                return rule
            }
        }
        
        logger.debug("Mock inference: no rule matched")
        return nil
    }
    
    /// Extracts simple keywords from a rule prompt for mock matching.
    private func extractKeywords(from prompt: String) -> [String] {
        // Common stop words to ignore
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
        
        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let reason):
                return "Failed to load MLX model: \(reason)"
            case .sessionNotInitialized:
                return "Chat session not initialized"
            case .inferenceFailed(let reason):
                return "Inference failed: \(reason)"
            }
        }
    }
}
