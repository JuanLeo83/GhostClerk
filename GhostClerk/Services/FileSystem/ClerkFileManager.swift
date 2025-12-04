//
//  ClerkFileManager.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import AppKit
import os.log

/// Service responsible for file operations: moving, renaming, and managing the Review Tray.
final class ClerkFileManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    static let shared = ClerkFileManager()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.juanleodev.GhostClerk", category: "ClerkFileManager")
    private let fileManager = FileManager.default
    
    /// Review Tray folder name
    private let reviewTrayFolderName = "_GhostReview"
    
    /// Ghost Clerk trash folder name (safety net)
    private let trashFolderName = ".ghost_clerk_trash"
    
    // MARK: - Computed Properties
    
    /// Returns the Downloads folder URL
    private var downloadsURL: URL {
        let homeDir = fileManager.homeDirectoryForCurrentUser
        if homeDir.path.contains("/Library/Containers/") {
            let realHome = URL(fileURLWithPath: NSHomeDirectory().components(separatedBy: "/Library/Containers/").first ?? NSHomeDirectory())
            return realHome.appendingPathComponent("Downloads")
        }
        return homeDir.appendingPathComponent("Downloads")
    }
    
    /// Returns the Review Tray folder URL
    var reviewTrayURL: URL {
        downloadsURL.appendingPathComponent(reviewTrayFolderName)
    }
    
    /// Returns the Ghost Clerk trash folder URL (inside Downloads for sandbox compatibility)
    private var trashURL: URL {
        downloadsURL.appendingPathComponent(trashFolderName)
    }
    
    // MARK: - Initialization
    
    private init() {
        ensureReviewTrayExists()
        ensureTrashExists()
    }
    
    // MARK: - Public API
    
    /// Moves a file to its destination based on a matched rule.
    /// Handles duplicates by renaming if necessary.
    /// - Parameters:
    ///   - sourceURL: The file to move
    ///   - rule: The matched rule containing the target path
    /// - Returns: The final destination URL, or nil if move failed
    @discardableResult
    func moveFile(_ sourceURL: URL, toRuleDestination rule: Rule) -> URL? {
        let destinationFolder = URL(fileURLWithPath: rule.targetPath)
        return moveFile(sourceURL, to: destinationFolder)
    }
    
    /// Moves a file to its destination based on a matched rule (async version).
    /// Handles duplicates by renaming if necessary.
    /// Uses security-scoped bookmarks for folders outside Downloads.
    /// - Parameters:
    ///   - sourceURL: The file to move
    ///   - rule: The matched rule containing the target path
    /// - Returns: The final destination URL, or nil if move failed
    @discardableResult
    func moveFileAsync(_ sourceURL: URL, toRuleDestination rule: Rule) async -> URL? {
        let destinationFolder = URL(fileURLWithPath: rule.targetPath)
        return await moveFileAsync(sourceURL, to: destinationFolder)
    }
    
    /// Moves a file to a specific destination folder (async version).
    /// Handles duplicates by comparing hashes and renaming if necessary.
    /// Uses security-scoped bookmarks for folders outside Downloads.
    /// - Parameters:
    ///   - sourceURL: The file to move
    ///   - destinationFolder: The target folder
    /// - Returns: The final destination URL, or nil if move failed
    @discardableResult
    func moveFileAsync(_ sourceURL: URL, to destinationFolder: URL) async -> URL? {
        let fileName = sourceURL.lastPathComponent
        var destinationURL = destinationFolder.appendingPathComponent(fileName)
        
        // Check if we need security-scoped access for this destination
        let needsBookmark = !destinationFolder.path.hasPrefix(downloadsURL.path)
        var accessedURL: URL? = nil
        
        if needsBookmark {
            // Try to get access via bookmark
            accessedURL = await BookmarkManager.shared.startAccessing(destinationFolder.path)
            if accessedURL == nil {
                logger.warning("No bookmark for \(destinationFolder.path) - trying direct access")
            }
        }
        
        // Use the accessed URL if available, otherwise try the original
        let targetFolder = accessedURL ?? destinationFolder
        
        defer {
            // Stop accessing the security-scoped resource when done
            if let accessed = accessedURL {
                Task {
                    await BookmarkManager.shared.stopAccessing(accessed)
                }
            }
        }
        
        // Ensure destination folder exists
        do {
            try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create destination folder: \(error.localizedDescription)")
            return nil
        }
        
        destinationURL = targetFolder.appendingPathComponent(fileName)
        
        // Check if file already exists at destination
        if fileManager.fileExists(atPath: destinationURL.path) {
            // Compare hashes
            let sourceHash = FileHasher.sha256(of: sourceURL)
            let destHash = FileHasher.sha256(of: destinationURL)
            
            if sourceHash == destHash && sourceHash != nil {
                // Same file, delete the source (move to trash)
                logger.info("Duplicate detected (same hash), removing source: \(fileName)")
                moveToTrash(sourceURL)
                return destinationURL
            } else {
                // Different content, rename
                destinationURL = generateUniqueFileName(for: destinationURL)
                logger.info("File exists with different content, renaming to: \(destinationURL.lastPathComponent)")
            }
        }
        
        // Perform the move
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            logger.info("Moved \(fileName) to \(targetFolder.path)")
            return destinationURL
        } catch {
            logger.error("Failed to move file: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Moves a file to a specific destination folder (synchronous version).
    /// Use this only for destinations that don't require security-scoped bookmarks (e.g., Downloads).
    /// - Parameters:
    ///   - sourceURL: The file to move
    ///   - destinationFolder: The target folder
    /// - Returns: The final destination URL, or nil if move failed
    @discardableResult
    func moveFile(_ sourceURL: URL, to destinationFolder: URL) -> URL? {
        let fileName = sourceURL.lastPathComponent
        var destinationURL = destinationFolder.appendingPathComponent(fileName)
        
        // Ensure destination folder exists
        do {
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create destination folder: \(error.localizedDescription)")
            return nil
        }
        
        // Check if file already exists at destination
        if fileManager.fileExists(atPath: destinationURL.path) {
            // Compare hashes
            let sourceHash = FileHasher.sha256(of: sourceURL)
            let destHash = FileHasher.sha256(of: destinationURL)
            
            if sourceHash == destHash && sourceHash != nil {
                // Same file, delete the source (move to trash)
                logger.info("Duplicate detected (same hash), removing source: \(fileName)")
                moveToTrash(sourceURL)
                return destinationURL
            } else {
                // Different content, rename
                destinationURL = generateUniqueFileName(for: destinationURL)
                logger.info("File exists with different content, renaming to: \(destinationURL.lastPathComponent)")
            }
        }
        
        // Perform the move
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            logger.info("Moved \(fileName) to \(destinationFolder.path)")
            return destinationURL
        } catch {
            logger.error("Failed to move file: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Moves a file to the Review Tray (for files that couldn't be classified).
    /// - Parameter sourceURL: The file to move
    /// - Returns: The destination URL in the Review Tray, or nil if failed
    @discardableResult
    func moveToReviewTray(_ sourceURL: URL) -> URL? {
        ensureReviewTrayExists()
        
        let fileName = sourceURL.lastPathComponent
        var destinationURL = reviewTrayURL.appendingPathComponent(fileName)
        
        // Handle duplicates in review tray
        if fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = generateUniqueFileName(for: destinationURL)
        }
        
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            logger.info("Moved \(fileName) to Review Tray")
            return destinationURL
        } catch {
            logger.error("Failed to move to Review Tray: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Moves a file to Ghost Clerk's trash (safety net).
    /// - Parameter sourceURL: The file to trash
    /// - Returns: The destination URL in trash, or nil if failed
    @discardableResult
    func moveToTrash(_ sourceURL: URL) -> URL? {
        ensureTrashExists()
        
        let fileName = sourceURL.lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let trashedName = "\(timestamp)_\(fileName)"
        let destinationURL = trashURL.appendingPathComponent(trashedName)
        
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            logger.info("Moved \(fileName) to Ghost Clerk trash")
            return destinationURL
        } catch {
            logger.error("Failed to move to trash: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Returns the count of files in the Review Tray.
    func reviewTrayCount() -> Int {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: reviewTrayURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return contents.count
        } catch {
            return 0
        }
    }
    
    /// Returns all files in the Review Tray.
    func reviewTrayFiles() -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: reviewTrayURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
    }
    
    /// Opens the Review Tray folder in Finder.
    func openReviewTray() {
        NSWorkspace.shared.open(reviewTrayURL)
    }
    
    // MARK: - Private Helpers
    
    /// Ensures the Review Tray folder exists.
    private func ensureReviewTrayExists() {
        if !fileManager.fileExists(atPath: reviewTrayURL.path) {
            do {
                try fileManager.createDirectory(at: reviewTrayURL, withIntermediateDirectories: true)
                logger.info("Created Review Tray folder")
            } catch {
                logger.error("Failed to create Review Tray folder: \(error.localizedDescription)")
            }
        }
    }
    
    /// Ensures the trash folder exists.
    private func ensureTrashExists() {
        if !fileManager.fileExists(atPath: trashURL.path) {
            do {
                try fileManager.createDirectory(at: trashURL, withIntermediateDirectories: true)
                logger.info("Created Ghost Clerk trash folder")
            } catch {
                logger.error("Failed to create trash folder: \(error.localizedDescription)")
            }
        }
    }
    
    /// Generates a unique filename by appending (1), (2), etc.
    private func generateUniqueFileName(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        var counter = 1
        var newURL = url
        
        while fileManager.fileExists(atPath: newURL.path) {
            let newName = ext.isEmpty ? "\(baseName)(\(counter))" : "\(baseName)(\(counter)).\(ext)"
            newURL = folder.appendingPathComponent(newName)
            counter += 1
            
            // Safety limit
            if counter > 1000 {
                logger.error("Too many duplicates for file: \(baseName)")
                break
            }
        }
        
        return newURL
    }
}
