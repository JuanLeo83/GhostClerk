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
        
        // Handle file system events
        dispatchSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.logger.info("🔔 DispatchSource event triggered for \(self.folderURL.path)")
            
            // Call the callback on main thread for UI updates
            DispatchQueue.main.async {
                self.onFolderDidChange?()
            }
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
    
    /// Returns the default Downloads folder URL
    static var defaultDownloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }
}
