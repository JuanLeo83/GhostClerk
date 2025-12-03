//
//  StorageService.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import os.log

/// Service responsible for persisting and loading Rules and ActivityLogs to/from JSON files.
/// Uses Application Support directory for storage (sandbox-safe).
actor StorageService {
    
    // MARK: - Singleton
    
    static let shared = StorageService()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.ghostclerk.app", category: "StorageService")
    private let fileManager = FileManager.default
    
    private let rulesFileName = "rules.json"
    private let logsFileName = "activity_logs.json"
    
    /// Maximum number of activity logs to retain
    private let maxLogEntries = 1000
    
    // MARK: - Computed Properties
    
    /// Returns the Application Support directory for Ghost Clerk
    private var appSupportDirectory: URL {
        get throws {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let ghostClerkDir = appSupport.appendingPathComponent("GhostClerk", isDirectory: true)
            
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: ghostClerkDir.path) {
                try fileManager.createDirectory(at: ghostClerkDir, withIntermediateDirectories: true)
                logger.info("Created app support directory at \(ghostClerkDir.path)")
            }
            
            return ghostClerkDir
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Rules CRUD
    
    /// Loads all rules from persistent storage
    func loadRules() async throws -> [Rule] {
        let fileURL = try appSupportDirectory.appendingPathComponent(rulesFileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.info("No rules file found, returning empty array")
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let rules = try decoder.decode([Rule].self, from: data)
            logger.info("Loaded \(rules.count) rules from storage")
            return rules
        } catch {
            logger.error("Failed to load rules: \(error.localizedDescription)")
            throw StorageError.loadFailed(underlying: error)
        }
    }
    
    /// Saves all rules to persistent storage
    func saveRules(_ rules: [Rule]) async throws {
        let fileURL = try appSupportDirectory.appendingPathComponent(rulesFileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rules)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Saved \(rules.count) rules to storage")
        } catch {
            logger.error("Failed to save rules: \(error.localizedDescription)")
            throw StorageError.saveFailed(underlying: error)
        }
    }
    
    /// Adds a new rule and persists to storage
    func addRule(_ rule: Rule) async throws -> [Rule] {
        var rules = try await loadRules()
        rules.append(rule)
        try await saveRules(rules)
        return rules
    }
    
    /// Updates an existing rule by ID
    func updateRule(_ rule: Rule) async throws -> [Rule] {
        var rules = try await loadRules()
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            throw StorageError.ruleNotFound(id: rule.id)
        }
        rules[index] = rule
        try await saveRules(rules)
        return rules
    }
    
    /// Deletes a rule by ID
    func deleteRule(id: UUID) async throws -> [Rule] {
        var rules = try await loadRules()
        rules.removeAll { $0.id == id }
        try await saveRules(rules)
        return rules
    }
    
    // MARK: - Activity Logs CRUD
    
    /// Loads all activity logs from persistent storage
    func loadLogs() async throws -> [ActivityLog] {
        let fileURL = try appSupportDirectory.appendingPathComponent(logsFileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.info("No logs file found, returning empty array")
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let logs = try decoder.decode([ActivityLog].self, from: data)
            logger.info("Loaded \(logs.count) activity logs from storage")
            return logs
        } catch {
            logger.error("Failed to load logs: \(error.localizedDescription)")
            throw StorageError.loadFailed(underlying: error)
        }
    }
    
    /// Saves all activity logs to persistent storage
    func saveLogs(_ logs: [ActivityLog]) async throws {
        let fileURL = try appSupportDirectory.appendingPathComponent(logsFileName)
        
        // Trim to max entries (keep most recent)
        let trimmedLogs = Array(logs.suffix(maxLogEntries))
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(trimmedLogs)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Saved \(trimmedLogs.count) activity logs to storage")
        } catch {
            logger.error("Failed to save logs: \(error.localizedDescription)")
            throw StorageError.saveFailed(underlying: error)
        }
    }
    
    /// Appends a new log entry and persists to storage
    func appendLog(_ log: ActivityLog) async throws {
        var logs = try await loadLogs()
        logs.append(log)
        try await saveLogs(logs)
    }
    
    /// Clears all activity logs
    func clearLogs() async throws {
        try await saveLogs([])
        logger.info("Cleared all activity logs")
    }
}

// MARK: - Storage Errors

enum StorageError: LocalizedError {
    case loadFailed(underlying: Error)
    case saveFailed(underlying: Error)
    case ruleNotFound(id: UUID)
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .ruleNotFound(let id):
            return "Rule not found with ID: \(id)"
        }
    }
}
