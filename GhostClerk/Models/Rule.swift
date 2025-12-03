//
//  Rule.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation

/// Represents a user-defined organization rule.
/// Rules are evaluated in order (first match wins).
struct Rule: Codable, Identifiable, Equatable {
    /// Unique identifier for the rule
    let id: UUID
    
    /// The natural language instruction written by the user
    /// Example: "Move invoices to the House folder"
    var naturalPrompt: String
    
    /// The destination folder path where matching files should be moved
    /// Example: "/Users/username/Documents/House"
    var targetPath: String
    
    /// Timestamp when the rule was created
    let createdAt: Date
    
    /// Whether the rule is currently active
    var isEnabled: Bool
    
    init(
        id: UUID = UUID(),
        naturalPrompt: String,
        targetPath: String,
        createdAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.naturalPrompt = naturalPrompt
        self.targetPath = targetPath
        self.createdAt = createdAt
        self.isEnabled = isEnabled
    }
}
