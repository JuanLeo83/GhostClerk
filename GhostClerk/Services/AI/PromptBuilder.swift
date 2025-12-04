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
    
    /// System prompt that defines the AI's role and behavior
    static let systemPrompt = """
    You are a file organization assistant. Your task is to analyze file content and determine which organizational rule best matches it.
    
    IMPORTANT RULES:
    1. You MUST respond with ONLY a single number (1, 2, 3, etc.) representing the matching rule.
    2. If NO rule matches the file content, respond with "0".
    3. Do NOT explain your reasoning. Just output the number.
    4. Be conservative - only match if you're confident the file belongs to that category.
    """
    
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
