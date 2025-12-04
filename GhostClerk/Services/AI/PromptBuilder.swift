//
//  PromptBuilder.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation

/// Builds prompts for the LLM to classify files based on user-defined rules.
/// This is a pure utility struct with no actor isolation.
struct PromptBuilder {
    
    /// Default system prompt that defines the AI's role and behavior
    static let defaultSystemPrompt = """
    You are a file organization assistant. Your task is to analyze files and match them to organizational rules.

    ANALYSIS PRIORITY:
    1. First, analyze the FILE NAME for clues (dates, keywords, company names)
    2. Then, analyze the FILE CONTENT for context

    LANGUAGE SUPPORT:
    - Understand documents in ANY language (Spanish, English, French, German, etc.)
    - Common translations: factura=invoice, contrato=contract, recibo=receipt, informe=report

    RESPONSE FORMAT:
    - Respond with ONLY a single number (1, 2, 3, etc.) representing the best matching rule
    - If NO rule clearly matches, respond with "0"
    - Do NOT explain your reasoning, just output the number

    MATCHING BEHAVIOR:
    - Be reasonably flexible - match if the content is clearly related to a rule
    - When uncertain between rules, prefer the one listed first (higher priority)
    - Only respond "0" if truly none of the rules apply
    """
    
    /// Gets the system prompt (custom or default)
    static var systemPrompt: String {
        let custom = UserDefaults.standard.string(forKey: "customSystemPrompt") ?? ""
        return custom.isEmpty ? defaultSystemPrompt : custom
    }
    
    /// Sets a custom system prompt
    static func setCustomPrompt(_ prompt: String) {
        UserDefaults.standard.set(prompt, forKey: "customSystemPrompt")
    }
    
    /// Resets to the default system prompt
    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: "customSystemPrompt")
    }
    
    /// Whether a custom prompt is being used
    static var isUsingCustomPrompt: Bool {
        let custom = UserDefaults.standard.string(forKey: "customSystemPrompt") ?? ""
        return !custom.isEmpty
    }
    
    /// Builds the user prompt with rules and file content
    /// - Parameters:
    ///   - rules: Array of user-defined rules (in priority order)
    ///   - fileName: Name of the file being analyzed
    ///   - extractedText: Text content extracted from the file
    /// - Returns: Formatted prompt string for the LLM
    static func buildPrompt(rules: [Rule], fileName: String, extractedText: String) -> String {
        guard !rules.isEmpty else {
            return ""
        }
        
        // Build numbered rule list
        let rulesList = rules.enumerated().map { index, rule in
            "\(index + 1). \(rule.naturalPrompt)"
        }.joined(separator: "\n")
        
        // Truncate text if too long (keep first 4000 chars for context)
        let truncatedText = extractedText.count > 4000 
            ? String(extractedText.prefix(4000)) + "..." 
            : extractedText
        
        return """
        RULES (in priority order):
        \(rulesList)
        
        FILE NAME: \(fileName)
        
        FILE CONTENT:
        \(truncatedText)
        
        Which rule number (1-\(rules.count)) best matches this file? If none match, respond with 0.
        """
    }
    
    /// Parses the LLM response to extract the rule index
    /// - Parameters:
    ///   - response: Raw response from the LLM
    ///   - rulesCount: Total number of rules available
    /// - Returns: The matching Rule's index (0-based), or nil if no match
    static func parseResponse(_ response: String, rulesCount: Int) -> Int? {
        // Clean the response - extract first number found
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to find a number at the start
        let scanner = Scanner(string: trimmed)
        var number: Int = 0
        
        if scanner.scanInt(&number) {
            // 0 means no match
            if number == 0 {
                return nil
            }
            // Valid rule index (convert 1-based to 0-based)
            if number >= 1 && number <= rulesCount {
                return number - 1
            }
        }
        
        // Fallback: try to find any digit in the response
        if let firstDigit = trimmed.first(where: { $0.isNumber }),
           let digit = Int(String(firstDigit)) {
            if digit == 0 {
                return nil
            }
            if digit >= 1 && digit <= rulesCount {
                return digit - 1
            }
        }
        
        return nil
    }
}
