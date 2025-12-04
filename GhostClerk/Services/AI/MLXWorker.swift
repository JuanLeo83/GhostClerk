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

/// Service responsible for running local LLM inference using MLX.
/// Uses a small, quantized model optimized for Apple Silicon.
actor MLXWorker {
    
    // MARK: - Singleton
    
    static let shared = MLXWorker()
    
    // MARK: - Configuration
    
    /// Model to use - Phi-3.5-mini is small (~2GB) and good for classification tasks
    /// Alternatives:
    /// - "mlx-community/Qwen3-4B-4bit" (~2.5GB) - Better reasoning
    /// - "mlx-community/Llama-3.2-1B-Instruct-4bit" (~0.7GB) - Faster, smaller
    private let modelId = "mlx-community/Phi-3.5-mini-instruct-4bit"
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.juanleodev.GhostClerk", category: "MLXWorker")
    
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
        defer { isLoading = false }
        
        logger.info("Loading MLX model: \(self.modelId)")
        
        do {
            // Load the model from Hugging Face using the simplified API
            let loadedModel = try await MLXLMCommon.loadModel(id: modelId)
            
            // Store the model context
            modelContext = loadedModel
            
            // Create a chat session
            chatSession = ChatSession(loadedModel)
            
            isModelLoaded = true
            logger.info("✅ Model loaded successfully: \(self.modelId)")
        } catch {
            logger.error("❌ Failed to load model: \(error.localizedDescription)")
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
    }
    
    /// Unloads the model from memory to free resources.
    func unloadModel() {
        modelContext = nil
        chatSession = nil
        isModelLoaded = false
        logger.info("Model unloaded")
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
