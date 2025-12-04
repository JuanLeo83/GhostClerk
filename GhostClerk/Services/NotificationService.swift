//
//  NotificationService.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import UserNotifications
import os.log

/// Service for sending native macOS notifications
final class NotificationService: NSObject {
    
    // MARK: - Singleton
    
    static let shared = NotificationService()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.juanleodev.GhostClerk", category: "NotificationService")
    private let center = UNUserNotificationCenter.current()
    
    /// Whether notifications are enabled (user preference)
    var isEnabled: Bool = true
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        center.delegate = self
        requestAuthorization()
    }
    
    // MARK: - Authorization
    
    private func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if granted {
                self?.logger.info("Notification permission granted")
            } else if let error = error {
                self?.logger.error("Notification permission error: \(error.localizedDescription)")
            } else {
                self?.logger.info("Notification permission denied")
            }
        }
    }
    
    // MARK: - Send Notifications
    
    /// Notifies that a file was successfully classified and moved
    func notifyFileMoved(fileName: String, destinationFolder: String) {
        guard isEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "File Organized"
        content.body = "\(fileName) → \(destinationFolder)"
        content.sound = .default
        content.categoryIdentifier = "FILE_MOVED"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        center.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Notifies that a file was sent to Review Tray
    func notifyFileNeedsReview(fileName: String) {
        guard isEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Review Needed"
        content.body = "\(fileName) couldn't be classified"
        content.sound = .default
        content.categoryIdentifier = "FILE_REVIEW"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        center.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Notifies that the AI model finished loading
    func notifyModelLoaded() {
        guard isEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Ghost Clerk Ready"
        content.body = "AI model loaded successfully"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "model_loaded",
            content: content,
            trigger: nil
        )
        
        center.add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    
    /// Handle notifications when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner even when app is active (menu bar app is always "active")
        completionHandler([.banner, .sound])
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Could open specific folders or Review Tray based on category
        let category = response.notification.request.content.categoryIdentifier
        
        if category == "FILE_REVIEW" {
            // Could trigger opening Review Tray
            NotificationCenter.default.post(name: .openReviewTray, object: nil)
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openReviewTray = Notification.Name("openReviewTray")
}
