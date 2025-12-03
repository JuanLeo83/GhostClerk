//
//  TextExtractor.swift
//  GhostClerk
//
//  Created by Ghost Clerk on 2025.
//

import Foundation
import PDFKit
import Vision
import AppKit
import os.log
import UniformTypeIdentifiers

/// Service responsible for extracting text content from files.
/// Supports PDFs (native text and OCR) and images (OCR).
final class TextExtractor: @unchecked Sendable {
    
    // MARK: - Singleton
    
    static let shared = TextExtractor()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.juanleodev.GhostClerk", category: "TextExtractor")
    
    /// Maximum text length to return (to avoid overwhelming the LLM)
    private let maxTextLength = 8000
    
    /// Supported file types for text extraction
    static let supportedExtensions: Set<String> = [
        "pdf",
        "png", "jpg", "jpeg", "tiff", "tif", "heic", "webp",
        "txt", "md", "markdown", "rtf"
    ]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Extracts text from a file at the given URL.
    /// Returns nil if extraction fails or file type is unsupported.
    func extractText(from url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        
        guard Self.supportedExtensions.contains(ext) else {
            logger.debug("Unsupported file type for text extraction: \(ext)")
            return nil
        }
        
        logger.info("Extracting text from: \(url.lastPathComponent)")
        
        do {
            let text: String?
            
            switch ext {
            case "pdf":
                text = try await extractFromPDF(url)
            case "png", "jpg", "jpeg", "tiff", "tif", "heic", "webp":
                text = try await extractFromImage(url)
            case "txt", "md", "markdown":
                text = try extractFromPlainText(url)
            case "rtf":
                text = try extractFromRTF(url)
            default:
                text = nil
            }
            
            guard let extractedText = text, !extractedText.isEmpty else {
                logger.warning("No text extracted from: \(url.lastPathComponent)")
                return nil
            }
            
            // Truncate if too long
            let finalText = truncateText(extractedText)
            logger.info("Extracted \(finalText.count) characters from: \(url.lastPathComponent)")
            
            return finalText
            
        } catch {
            logger.error("Text extraction failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Checks if a file type is supported for text extraction
    func isSupported(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }
    
    // MARK: - PDF Extraction
    
    /// Extracts text from a PDF file.
    /// First attempts native text extraction, falls back to OCR if needed.
    private func extractFromPDF(_ url: URL) async throws -> String? {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ExtractionError.unableToOpenFile
        }
        
        // Try native text extraction first
        if let nativeText = pdfDocument.string, !nativeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.debug("PDF has native text: \(url.lastPathComponent)")
            return cleanText(nativeText)
        }
        
        // Fall back to OCR for scanned PDFs
        logger.debug("PDF appears scanned, using OCR: \(url.lastPathComponent)")
        return try await ocrPDF(pdfDocument)
    }
    
    /// Performs OCR on each page of a PDF document.
    private func ocrPDF(_ document: PDFDocument) async throws -> String? {
        var allText: [String] = []
        let pageCount = min(document.pageCount, 10) // Limit to first 10 pages
        
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            // Render page to image
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0 // Higher resolution for better OCR
            let imageSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            let image = NSImage(size: imageSize, flipped: false, drawingHandler: { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.setFillColor(NSColor.white.cgColor)
                context.fill(rect)
                context.translateBy(x: 0, y: rect.height)
                context.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context)
                return true
            })
            
            // Convert to CGImage for Vision
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }
            
            if let pageText = try await performOCR(on: cgImage) {
                allText.append(pageText)
            }
        }
        
        return allText.isEmpty ? nil : allText.joined(separator: "\n\n--- Page Break ---\n\n")
    }
    
    // MARK: - Image Extraction (OCR)
    
    /// Extracts text from an image file using Vision OCR.
    private func extractFromImage(_ url: URL) async throws -> String? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExtractionError.unableToOpenFile
        }
        
        return try await performOCR(on: cgImage)
    }
    
    /// Performs OCR using Vision framework.
    private func performOCR(on cgImage: CGImage) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            
            // Configure for best accuracy
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "es-ES"] // English and Spanish
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Plain Text Extraction
    
    /// Extracts text from plain text files (.txt, .md).
    private func extractFromPlainText(_ url: URL) throws -> String? {
        let text = try String(contentsOf: url, encoding: .utf8)
        return cleanText(text)
    }
    
    /// Extracts text from RTF files.
    private func extractFromRTF(_ url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        let attributedString = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return cleanText(attributedString.string)
    }
    
    // MARK: - Text Processing
    
    /// Cleans extracted text by normalizing whitespace.
    private func cleanText(_ text: String) -> String {
        // Replace multiple whitespaces/newlines with single space
        let cleaned = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return cleaned
    }
    
    /// Truncates text to maximum length, preserving word boundaries.
    private func truncateText(_ text: String) -> String {
        guard text.count > maxTextLength else { return text }
        
        let truncated = String(text.prefix(maxTextLength))
        
        // Find last space to avoid cutting mid-word
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        
        return truncated + "..."
    }
    
    // MARK: - Errors
    
    enum ExtractionError: LocalizedError {
        case unableToOpenFile
        case unsupportedFileType
        case ocrFailed
        
        var errorDescription: String? {
            switch self {
            case .unableToOpenFile:
                return "Unable to open file for text extraction"
            case .unsupportedFileType:
                return "File type not supported for text extraction"
            case .ocrFailed:
                return "OCR processing failed"
            }
        }
    }
}
