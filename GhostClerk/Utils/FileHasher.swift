//
//  FileHasher.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import CryptoKit
import os.log

/// Utility for calculating file hashes using SHA-256.
/// Used to detect duplicate files by content comparison.
enum FileHasher {
    
    private static let logger = Logger(subsystem: "com.ghostclerk.app", category: "FileHasher")
    
    /// Buffer size for streaming hash calculation (1MB)
    private static let bufferSize = 1024 * 1024
    
    /// Calculates SHA-256 hash of a file using streaming to handle large files efficiently.
    /// - Parameter url: The file URL to hash
    /// - Returns: Hex string of the SHA-256 hash, or nil if the file cannot be read
    static func sha256(of url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.warning("File does not exist: \(url.path)")
            return nil
        }
        
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            logger.error("Cannot open file for reading: \(url.path)")
            return nil
        }
        
        defer {
            try? fileHandle.close()
        }
        
        var hasher = SHA256()
        
        do {
            while let data = try fileHandle.read(upToCount: bufferSize), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            logger.error("Error reading file for hash: \(error.localizedDescription)")
            return nil
        }
        
        let digest = hasher.finalize()
        let hashString = digest.map { String(format: "%02x", $0) }.joined()
        
        logger.debug("Hash calculated for \(url.lastPathComponent): \(hashString.prefix(16))...")
        return hashString
    }
    
    /// Compares two files by their SHA-256 hash.
    /// - Parameters:
    ///   - url1: First file URL
    ///   - url2: Second file URL
    /// - Returns: True if both files have the same hash (identical content)
    static func areFilesIdentical(_ url1: URL, _ url2: URL) -> Bool {
        guard let hash1 = sha256(of: url1),
              let hash2 = sha256(of: url2) else {
            return false
        }
        return hash1 == hash2
    }
}
