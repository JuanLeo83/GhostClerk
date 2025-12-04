import Foundation
import os

/// Manages retry logic for files that couldn't be processed (locked, incomplete downloads, etc.)
actor RetryQueue {
    
    // MARK: - Types
    
    struct PendingFile: Sendable {
        let url: URL
        var attemptCount: Int
        var lastAttempt: Date
        var nextRetry: Date
    }
    
    // MARK: - Configuration
    
    private let maxRetries = 5
    private let baseDelay: TimeInterval = 5 // seconds
    private let maxDelay: TimeInterval = 60 // cap at 1 minute
    
    // MARK: - State
    
    private var pendingFiles: [URL: PendingFile] = [:]
    private var retryTimer: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.juanleodev.GhostClerk", category: "RetryQueue")
    
    /// Callback when a file is ready for retry
    private var onRetry: ((URL) async -> Bool)?
    
    // MARK: - Lifecycle
    
    func start(onRetry: @escaping (URL) async -> Bool) {
        self.onRetry = onRetry
        startRetryLoop()
        logger.info("RetryQueue started")
    }
    
    func stop() {
        retryTimer?.cancel()
        retryTimer = nil
        logger.info("RetryQueue stopped")
    }
    
    // MARK: - Public API
    
    /// Enqueue a file for retry
    func enqueue(_ url: URL) {
        if let existing = pendingFiles[url] {
            // Already queued, update attempt count
            var updated = existing
            updated.attemptCount += 1
            updated.lastAttempt = Date()
            updated.nextRetry = calculateNextRetry(attempt: updated.attemptCount)
            
            if updated.attemptCount >= maxRetries {
                pendingFiles.removeValue(forKey: url)
                logger.warning("File exceeded max retries, giving up: \(url.lastPathComponent)")
            } else {
                pendingFiles[url] = updated
                logger.debug("Retry #\(updated.attemptCount) scheduled for: \(url.lastPathComponent)")
            }
        } else {
            // New file
            let pending = PendingFile(
                url: url,
                attemptCount: 1,
                lastAttempt: Date(),
                nextRetry: calculateNextRetry(attempt: 1)
            )
            pendingFiles[url] = pending
            logger.debug("File queued for retry: \(url.lastPathComponent)")
        }
    }
    
    /// Remove a file from the retry queue (e.g., when successfully processed elsewhere)
    func dequeue(_ url: URL) {
        if pendingFiles.removeValue(forKey: url) != nil {
            logger.debug("File removed from retry queue: \(url.lastPathComponent)")
        }
    }
    
    /// Check if a file is pending retry
    func isPending(_ url: URL) -> Bool {
        pendingFiles[url] != nil
    }
    
    /// Get count of pending files
    var pendingCount: Int {
        pendingFiles.count
    }
    
    // MARK: - Private Methods
    
    /// Calculate next retry time using exponential backoff
    private func calculateNextRetry(attempt: Int) -> Date {
        // Exponential backoff: 5s, 10s, 20s, 40s, 60s (capped)
        let delay = min(baseDelay * pow(2, Double(attempt - 1)), maxDelay)
        return Date().addingTimeInterval(delay)
    }
    
    private func startRetryLoop() {
        retryTimer?.cancel()
        retryTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Check every 2 seconds
                await self?.processRetries()
            }
        }
    }
    
    private func processRetries() async {
        let now = Date()
        var toRetry: [URL] = []
        
        for (url, pending) in pendingFiles {
            if pending.nextRetry <= now {
                toRetry.append(url)
            }
        }
        
        for url in toRetry {
            guard let onRetry = onRetry else { continue }
            
            logger.debug("Retrying file: \(url.lastPathComponent)")
            
            // Check if file still exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                pendingFiles.removeValue(forKey: url)
                logger.debug("File no longer exists, removing from queue: \(url.lastPathComponent)")
                continue
            }
            
            // Attempt to process
            let success = await onRetry(url)
            
            if success {
                pendingFiles.removeValue(forKey: url)
                logger.info("Retry successful for: \(url.lastPathComponent)")
            } else {
                // Re-enqueue (will increment attempt count or remove if max exceeded)
                enqueue(url)
            }
        }
    }
}
