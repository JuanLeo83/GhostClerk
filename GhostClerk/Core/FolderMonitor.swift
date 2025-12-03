//
//  FolderMonitor.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import os.log

/// Monitors a folder for file system changes using GCD's DispatchSource.
/// This is the core watcher that triggers the file processing pipeline.
final class FolderMonitor {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.ghostclerk.app", category: "FolderMonitor")
    
    /// The URL of the folder being monitored
    let folderURL: URL
    
    /// File descriptor for the monitored folder
    private var fileDescriptor: Int32 = -1
    
    /// Dispatch source for monitoring file system events
    private var dispatchSource: DispatchSourceFileSystemObject?
    
    /// Queue for handling file system events
    private let monitorQueue = DispatchQueue(label: "com.ghostclerk.foldermonitor", qos: .utility)
    
    /// Callback triggered when changes are detected
    var onFolderDidChange: (() -> Void)?
    
    /// Whether the monitor is currently active
    private(set) var isMonitoring = false
    
    /// Debounce work item to coalesce rapid events
    private var debounceWorkItem: DispatchWorkItem?
    
    /// Debounce interval in seconds
    private let debounceInterval: TimeInterval = 0.5
    
    // MARK: - Initialization
    
    /// Creates a new FolderMonitor for the specified URL
    /// - Parameter url: The folder URL to monitor (e.g., ~/Downloads)
    init(url: URL) {
        self.folderURL = url
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    /// Starts monitoring the folder for changes
    func start() {
        guard !isMonitoring else {
            logger.warning("Monitor already running for \(self.folderURL.path)")
            return
        }
        
        // Open file descriptor for the folder
        fileDescriptor = open(folderURL.path, O_EVTONLY)
        
        guard fileDescriptor != -1 else {
            logger.error("Failed to open file descriptor for \(self.folderURL.path)")
            return
        }
        
        // Create dispatch source to monitor all file system events
        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .all,
            queue: monitorQueue
        )
        
        // Handle file system events with debounce
        dispatchSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.logger.debug("🔔 DispatchSource event triggered for \(self.folderURL.path)")
            
            // Cancel any pending debounce
            self.debounceWorkItem?.cancel()
            
            // Create new debounced work item
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.logger.info("🔔 Folder change detected (debounced)")
                DispatchQueue.main.async {
                    self.onFolderDidChange?()
                }
            }
            self.debounceWorkItem = workItem
            
            // Schedule after debounce interval
            DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
        
        // Handle cancellation
        dispatchSource?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
            self.logger.info("Monitor stopped for \(self.folderURL.path)")
        }
        
        // Start monitoring
        dispatchSource?.resume()
        isMonitoring = true
        logger.info("Started monitoring \(self.folderURL.path)")
    }
    
    /// Stops monitoring the folder
    func stop() {
        guard isMonitoring else { return }
        
        dispatchSource?.cancel()
        dispatchSource = nil
        isMonitoring = false
    }
    
    // MARK: - Static Helpers
    
    /// Returns the default Downloads folder URL (real user folder, not sandbox)
    static var defaultDownloadsURL: URL {
        // Use NSHomeDirectoryForUser to get the real home, not the sandbox container
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        // Check if we're in a sandbox container
        if homeDir.path.contains("/Library/Containers/") {
            // Extract the real username and build the path
            let realHome = URL(fileURLWithPath: NSHomeDirectory().components(separatedBy: "/Library/Containers/").first ?? NSHomeDirectory())
            return realHome.appendingPathComponent("Downloads")
        }
        return homeDir.appendingPathComponent("Downloads")
    }
}
