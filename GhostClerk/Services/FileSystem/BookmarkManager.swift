//
//  BookmarkManager.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import os.log

/// Manages Security-Scoped Bookmarks for persistent folder access outside the sandbox.
/// When a user selects a folder via the file picker, we save a bookmark to maintain
/// access in future app sessions.
actor BookmarkManager {
    
    // MARK: - Singleton
    
    static let shared = BookmarkManager()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.juanleodev.GhostClerk", category: "BookmarkManager")
    private let userDefaults = UserDefaults.standard
    private let bookmarksKey = "SecurityScopedBookmarks"
    
    /// Currently active security-scoped URLs (need to call stopAccessingSecurityScopedResource when done)
    private var activeAccessURLs: Set<URL> = []
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Saves a security-scoped bookmark for a URL selected by the user.
    /// Call this when the user selects a folder via NSOpenPanel/fileImporter.
    func saveBookmark(for url: URL) throws {
        // Start accessing to create bookmark
        guard url.startAccessingSecurityScopedResource() else {
            logger.warning("Failed to start accessing security scoped resource: \(url.path)")
            // Continue anyway, might work for Downloads
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            var bookmarks = loadBookmarksData()
            bookmarks[url.path] = bookmarkData
            saveBookmarksData(bookmarks)
            
            logger.info("Saved bookmark for: \(url.path)")
        } catch {
            logger.error("Failed to create bookmark for \(url.path): \(error.localizedDescription)")
            throw BookmarkError.failedToCreate(error.localizedDescription)
        }
    }
    
    /// Resolves a saved bookmark and starts accessing the security-scoped resource.
    /// Returns the resolved URL if successful, nil otherwise.
    /// IMPORTANT: Call `stopAccessing(_:)` when done with the URL.
    func startAccessing(_ path: String) -> URL? {
        let bookmarks = loadBookmarksData()
        
        guard let bookmarkData = bookmarks[path] else {
            logger.debug("No bookmark found for: \(path)")
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                logger.warning("Bookmark is stale for: \(path), attempting to refresh")
                // Try to refresh the bookmark
                if url.startAccessingSecurityScopedResource() {
                    try? saveBookmark(for: url)
                }
            }
            
            if url.startAccessingSecurityScopedResource() {
                activeAccessURLs.insert(url)
                logger.debug("Started accessing: \(url.path)")
                return url
            } else {
                logger.warning("Failed to start accessing security scoped resource: \(url.path)")
                return nil
            }
        } catch {
            logger.error("Failed to resolve bookmark for \(path): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Stops accessing a security-scoped resource.
    func stopAccessing(_ url: URL) {
        if activeAccessURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeAccessURLs.remove(url)
            logger.debug("Stopped accessing: \(url.path)")
        }
    }
    
    /// Stops accessing all active security-scoped resources.
    func stopAccessingAll() {
        for url in activeAccessURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeAccessURLs.removeAll()
        logger.info("Stopped accessing all security scoped resources")
    }
    
    /// Checks if we have a saved bookmark for a path.
    func hasBookmark(for path: String) -> Bool {
        loadBookmarksData()[path] != nil
    }
    
    /// Removes a saved bookmark.
    func removeBookmark(for path: String) {
        var bookmarks = loadBookmarksData()
        bookmarks.removeValue(forKey: path)
        saveBookmarksData(bookmarks)
        logger.info("Removed bookmark for: \(path)")
    }
    
    /// Returns all saved bookmark paths.
    func allBookmarkedPaths() -> [String] {
        Array(loadBookmarksData().keys)
    }
    
    // MARK: - Private Helpers
    
    private func loadBookmarksData() -> [String: Data] {
        userDefaults.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }
    
    private func saveBookmarksData(_ bookmarks: [String: Data]) {
        userDefaults.set(bookmarks, forKey: bookmarksKey)
    }
    
    // MARK: - Errors
    
    enum BookmarkError: LocalizedError {
        case failedToCreate(String)
        case failedToResolve(String)
        
        var errorDescription: String? {
            switch self {
            case .failedToCreate(let reason):
                return "Failed to create bookmark: \(reason)"
            case .failedToResolve(let reason):
                return "Failed to resolve bookmark: \(reason)"
            }
        }
    }
}
