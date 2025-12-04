//
//  ActivityLog.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation

/// Represents a single activity entry in the processing log.
struct ActivityLog: Codable, Identifiable {
    /// Unique identifier for the log entry
    let id: UUID
    
    /// When the action occurred
    let timestamp: Date
    
    /// Original file name that was processed
    let fileName: String
    
    /// The action that was taken on the file
    let action: ActionType
    
    /// The outcome of the action
    let status: ActionStatus
    
    /// Optional: The rule ID that was matched (nil if no rule matched)
    let matchedRuleId: UUID?
    
    /// Optional: Additional details or error message
    let details: String?
    
    /// Optional: Original file path before move (for undo)
    let sourcePath: String?
    
    /// Optional: Destination file path after move (for undo)
    let destinationPath: String?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        fileName: String,
        action: ActionType,
        status: ActionStatus,
        matchedRuleId: UUID? = nil,
        details: String? = nil,
        sourcePath: String? = nil,
        destinationPath: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fileName = fileName
        self.action = action
        self.status = status
        self.matchedRuleId = matchedRuleId
        self.details = details
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
    
    /// Whether this action can be undone
    var canUndo: Bool {
        return (action == .moved || action == .reviewTray) 
            && status == .success 
            && sourcePath != nil 
            && destinationPath != nil
    }
}

// MARK: - Action Type

/// The type of action performed on a file
enum ActionType: String, Codable {
    case scanned       // File was detected and scanned
    case moved         // File was moved to a destination
    case renamed       // File was renamed (duplicate with different content)
    case deleted       // File was moved to Ghost Trash (duplicate with same hash)
    case whitelisted   // File was ignored (installer/app)
    case reviewTray    // File was moved to review tray (unclassifiable)
    case skipped       // File was skipped (temporary download file)
}

// MARK: - Action Status

/// The outcome status of an action
enum ActionStatus: String, Codable {
    case success       // Action completed successfully
    case failed        // Action failed (see details for reason)
    case pending       // Action is waiting (e.g., file locked)
    case retrying      // Action will be retried
}
