# Ghost Clerk v1.1 - Task List (Swift Native)

## 0. Setup & Infrastructure (Foundations)

Critical configuration tasks for the Xcode project, system permissions, and dependencies. Without this, nothing starts.

- [x] **Init Project**: Create macOS App project in Xcode (SwiftUI). Configure minimum target macOS 14.0.
- [x] **Agent Mode**: Modify `Info.plist` setting `Application is agent (UIElement)` to `YES` to hide the Dock icon.
- [x] **Dependencies**: Add Swift Package Manager package: `mlx-swift-lm` (https://github.com/ml-explore/mlx-swift-lm).
- [x] **Permissions (Sandbox)**: Configure *Entitlements*: `com.apple.security.files.user-selected.read-write` and `com.apple.security.files.downloads.read-write`.
- [x] **File Structure**: Create groups in Xcode: `Core`, `Services`, `Models`, `Views`, `Utils`.
- [x] **Data Models**: Define `Codable` structs in `Models/`:
    - `Rule.swift` (`id`, `naturalPrompt`, `targetPath`).
    - `ActivityLog.swift` (`timestamp`, `fileName`, `action`, `status`).
- [x] **Persistence Layer**: Implement `Services/StorageService.swift` to save/load JSONs (`rules.json`, `activity.log`) in `ApplicationSupport`.

## Story 2: Core Loop & Immunity (Blocking)

The monitoring and filtering engine. Prioritized over Story 1 because we need to detect files before applying rules.

- [x] **File Watcher**: Implement `Core/FolderMonitor.swift` using `DispatchSource` to listen for `write` events in `~/Downloads`.
- [x] **Processing Queue**: Simplified - FileProcessor handles serial processing directly.
- [x] **Immunity System (Whitelist)**: Implemented in FileProcessor. Ignores `.crdownload`, `.part`, `.download`, `.tmp`, `.partial`, `.dmg`, `.pkg`, `.app`, `.iso`.
- [x] **Lock Check Strategy**: Implemented in FileProcessor with file age debounce and lock detection.
- [x] **File Hasher**: Implemented `Utils/FileHasher.swift` using CryptoKit SHA256 streaming.

## Story 1: Intelligence & Rules (The Brain)

Integration of MLX and Business Logic.

- [x] **Prompt Builder**: Create `Services/AI/PromptBuilder.swift`. Formats rules as numbered list for LLM.
- [x] **MLX Service**: Implement `Services/AI/MLXWorker.swift`.
    - Mock inference with keyword matching (ready for real MLX integration).
    - Structure prepared for Phi-3.5-mini model loading.
- [x] **MLX Package**: Add `mlx-swift-lm` dependency and integrate real AI inference.
- [x] **Rules UI**: Implement rule editing in `Views/SettingsView.swift` with add/edit/delete support.
- [x] **Security-Scoped Bookmarks**: Implement `Services/FileSystem/BookmarkManager.swift` for persistent folder access outside sandbox.

## Story 2 (Cont.): Extraction & OCR (The Eyes)

Ability to read content.

- [x] **Text Extractor Service**: Implement `Services/Vision/TextExtractor.swift`.
    - **Step 1**: PDFKit (`PDFDocument(url).string`) for native PDFs.
    - **Step 2**: Vision Framework (`VNRecognizeTextRequest`) for OCR of images/scanned PDFs.
    - Supports: PDF, PNG, JPG, JPEG, TIFF, HEIC, WEBP, TXT, MD, RTF.

## Story 3: Duplicate Management (Integrity)

Prevent data overwriting.

- [x] **Hash Utility**: `Utils/FileHasher.swift` using CryptoKit SHA-256 (streaming).
- [x] **Duplicate Logic**: Implemented in `Services/FileSystem/ClerkFileManager.swift`:
    - Check existence at destination.
    - Compare Hash.
    - Decision: `delete` (if hash equal) or `rename` (if hash different).
- [x] **Rename Helper**: Function that generates `file(1).pdf`, `file(2).pdf` recursively.

## Story 4: Review Tray & UI (Feedback)

Uncertainty management and User Interface.

- [x] **Review Tray Logic**: If MLX returns `nil`, move file to `~/Downloads/_GhostReview` folder.
- [x] **MenuBar UI**: Implemented `GhostClerkApp.swift` (MenuBarExtra):
    - Show status ("Monitoring Active" / "Monitoring Paused").
    - Button to open Settings.
    - Button to open Review Tray with count badge.
- [x] **Visual Alert**: Badge counter on menu bar icon when Review Tray has files.
- [x] **Alert Banners**: Contextual alerts in menu (paused, no rules, files need review).

## Story 5: Safety Net

Disaster prevention.

- [x] **Trash Logic**: Implemented in `Services/FileSystem/ClerkFileManager.swift`.
    - Any duplicate file deletion moves to `~/.ghost_clerk_trash` with timestamp.