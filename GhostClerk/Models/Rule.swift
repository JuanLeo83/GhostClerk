//
//  Rule.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation

/// Represents a user-defined organization rule.
/// Rules are evaluated in priority order (lower number = higher priority).
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
    
    /// Priority order (0 = highest priority, evaluated first)
    var priority: Int
    
    init(
        id: UUID = UUID(),
        naturalPrompt: String,
        targetPath: String,
        createdAt: Date = Date(),
        isEnabled: Bool = true,
        priority: Int = Int.max // New rules go to the bottom by default
    ) {
        self.id = id
        self.naturalPrompt = naturalPrompt
        self.targetPath = targetPath
        self.createdAt = createdAt
        self.isEnabled = isEnabled
        self.priority = priority
    }
    
    // Custom decoder to handle existing rules without priority field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        naturalPrompt = try container.decode(String.self, forKey: .naturalPrompt)
        targetPath = try container.decode(String.self, forKey: .targetPath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        // Default priority for existing rules that don't have it
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }
}
