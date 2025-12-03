# Plan: Core Logic (Ghost Clerk v1.1 - macOS Native)

**Reference Spec**: Ghost Clerk v1.1 PRD (Swift Revision)

## Technical Context (Stack & Scope)

- **Language**: Swift 5.10+ (macOS 14+ Target).
- **UI Framework**: SwiftUI (Declarative Interface) + `MenuBarExtra` (Tray Management).
- **AI Stack (Apple Silicon)**:
    - **Reasoning/NLP**: `MLX Swift` running `Phi-3.5-mini-instruct` (4-bit quant, GGUF/MLX format).
    - **OCR/Vision**: Native `Vision` framework (`VNRecognizeTextRequest`) and `PDFKit`.
- **Persistence**:
    - **Rules**: Local JSON file (`rules.json`) in AppSupport.
    - **Logs**: Rotating JSON file (`activity.log`) in AppSupport.
- **Key Native Libraries**:
    - `DispatchSource`: For file system monitoring (Low-level File Watcher).
    - `CryptoKit`: For efficient SHA-256 hash calculation.
    - `FileHandle`: For secure read/write management.

## Technical Design Decisions

1. **[Sequential Pipeline (OperationQueue)]**:
    - An `OperationQueue` with `maxConcurrentOperationCount = 1` will be used.
    - **Reason**: Although M1/M2/M3 chips are powerful, loading the model into memory and performing OCR concurrently on 10 files would spike memory usage (Unified Memory) and overheat the device. Processing will be strictly **FIFO** (First In, First Out).

2. **[Hybrid Extraction Strategy (PDFKit + Vision)]**:
    - **Step 1 (Fast)**: Attempt native text extraction using `PDFKit` (`PDFDocument.string`). Computational cost is near zero.
    - **Step 2 (Visual Fallback)**: If extracted text is nil or very short (< 50 characters), assume scanned PDF or Image. Invoke `VNRecognizeTextRequest` from the `Vision` framework (runs on Neural Engine).

3. **[Deterministic Classification Logic]**:
    - The Prompt for Phi-3.5 will not decide based on fuzzy probability, but on **strict matching**.
    - **Prompt Engineering**: Rules will be injected sequentially numbered (1, 2, 3...). The instruction will be: "Evaluate the text against these rules in order. Return the ID of the **first** rule that matches. If none match, return NULL".
    - This transfers the "Sequential Priority" logic from code to the Prompt, simplifying the Swift algorithm.

4. **[Immunity System (Pre-Process Whitelist)]**:
    - Before queuing any file for OCR/AI, an extension filter will be applied.
    - **Ignore (Hard skip)**: `.crdownload`, `.part`, `.download`, hidden files (`.*`).
    - **Whitelist (Soft skip)**: `.dmg`, `.pkg`, `.app`, `.iso`. These are logged as "Whitelisted" and are neither moved nor processed.

5. **[Duplicate Management (CryptoKit)]**:
    - The SHA-256 of the source file will be calculated (`FileHandle` stream to avoid loading large files into RAM).
    - Atomic "Check-and-Act" logic to avoid race conditions if the user manually moves files while the app is thinking.

## Xcode Project Structure

```text
GhostClerk/
├── App/
│   ├── GhostClerkApp.swift      <-- Entry Point (@main, MenuBarExtra)
│   └── AppState.swift           <-- Global ObservableObject (Main ViewModel)
│
├── Core/
│   ├── FileWatcher/
│   │   └── FolderMonitor.swift  <-- DispatchSource Wrapper
│   ├── Pipeline/
│   │   ├── ProcessingQueue.swift <-- OperationQueue Wrapper
│   │   └── FileOperation.swift   <-- Unitary logic for a single file
│   └── Utils/
│       ├── FileHash.swift       <-- CryptoKit helpers
│       └── RetryPolicy.swift    <-- Exponential Backoff logic
│
├── Services/
│   ├── AI/
│   │   ├── MLXWorker.swift      <-- Singleton keeping the model in memory
│   │   └── PromptBuilder.swift  <-- String generator for LLM
│   ├── Vision/
│   │   └── TextExtractor.swift  <-- PDFKit + Vision Logic
│   └── FileSystem/
│       └── ClerkFileManager.swift <-- Move, Rename, Delete (Sandboxed)
│
├── Models/
│   ├── Rule.swift               <-- Codable (id, naturalPrompt, targetPath)
│   ├── ProcessingEvent.swift    <-- Enum (scan, match, move, error)
│   └── FileType.swift           <-- Helpers to detect extensions
│
└── Views/
    ├── Settings/
    │   ├── RulesListView.swift  <-- Drag & Drop interface
    │   └── AddRuleView.swift
    └── Menu/
        ├── StatusView.swift     <-- "Processing: Invoice.pdf..."
        └── ActivityLogView.swift
        
```

## Data Flow (Execution Pipeline)
1. **Monitor**: `FolderMonitor` detects `invoice.pdf` in `~/Downloads` (Event `write`).
2. **Filter 1**: Is it `.crdownload`? -> **IGNORE**.
3. **Filter 2**: Is it `.dmg`? -> **LOG("Whitelisted")** -> END.
4. **Queueing**: A `FileOperation` is created and added to `ProcessingQueue`.
5. **Execution (Async)**: a. **Lock Check**: Can it be opened for reading? (If not -> Retry later). b. **Hash**: Calculate SHA-256. c. **Extractor**: Get `String` (PDFKit or Vision). d. **Inference**: `MLXWorker` receives `(Text, [Rules])` -> Returns `RuleID` or `nil`. e. **Action**: - If `RuleID`: Check destination. File exists? -> Compare Hashes -> Delete or Rename -> Move. - If `nil`: Move to "Review Tray" folder.
6. **Log**: Save result to `activity.log` and update `AppState` (UI).