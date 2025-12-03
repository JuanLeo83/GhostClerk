# Product Requirements Document (PRD): Ghost Clerk v1.1

**Version:** 1.1 (Swift/MVP Technical Revision)
**Status:** Ready for Development
**Scope:** MVP (Minimum Viable Product)

## Concept Summary
Ghost Clerk is a local, private, and silent desktop file organizer for macOS. It uses Natural Language Processing (Local LLM) and native OCR to automatically classify downloads. Its philosophy is "Install and forget," minimizing user interaction and ensuring that no data ever leaves the device.

---

## User Stories (The What)

### Story 1: Natural Configuration and Sequential Priority (Priority: 1)
**As a** user, **I want** to configure rules using natural language and order them visually, **so that** I have deterministic control over which rule is applied first without ambiguous conflicts.

**Acceptance Criteria:**
1. **Given** that the user writes an instruction (e.g., "Invoices to House folder"), **When** it is saved, **Then** the system translates it into an internally executable rule.
2. **Given** a file that theoretically meets two different rules, **When** the system evaluates which one to apply, **Then** it must strictly apply the **"First Match Wins"** logic based on the visual order of the rule list (top to bottom).
3. **Given** a list of rules, **When** the user drags a rule upwards, **Then** its evaluation priority increases immediately.

### Story 2: Intelligent Organization with Native OCR (Priority: 1)
**As a** user, **I want** the system to read the content of my files (including scanned images), **so that** it classifies documents based on what they are and not what they are called.

**Acceptance Criteria:**
1. **Given** a downloaded file, **When** the system processes it, **Then** it uses the `Vision` framework (macOS) to extract text from images/PDFs or direct reading if it is plain text.
2. **Given** a processed file, **When** it is moved to its destination, **Then** an entry is generated in the activity log accessible from the `MenuBarExtra` (Tray).

### Story 3: Duplicate Management by Hash (Priority: 1)
**As a** user, **I want** to avoid having identical copies of the same file in the destination, **so that** I optimize space and keep order.

**Acceptance Criteria:**
1. **Given** that a file is downloaded and one with the same name already exists **in the destination folder**, **When** the system detects that the **hash (SHA-256)** of both is identical, **Then** it deletes the newly downloaded file (redundant download assumed).
2. **Given** the same case as above, **When** the hashes are different (content varies), **Then** the system renames the new file sequentially (`file(2).pdf`) and saves it without overwriting.

### Story 4: Review Tray and Immunity (Priority: 1)
**As a** user, **I want** files the system doesn't understand to be set aside, but my installers and apps to stay where they are, **so that** my immediate workflow is not interrupted.

**Acceptance Criteria:**
1. **Given** an unknown binary file, unreadable file, or one that does not reach the confidence threshold, **When** it is processed, **Then** it is moved to the physical "Review Tray" folder.
2. **Given** an "Installer/App" type file (`.dmg`, `.pkg`, `.app`, `.iso`), **When** it is detected, **Then** it is **IGNORED** (Whitelisted) and remains in the original downloads folder. It is not moved to review.
3. **Given** that there are new items in the review tray, **When** the move occurs, **Then** the menu bar icon changes its visual state.

### Story 5: Safety Net (Virtual Trash) (Priority: 2)
**As a** cautious user, **I want** the system never to permanently delete anything on its own, **so that** I avoid catastrophic accidents.

**Acceptance Criteria:**
1. **Given** a rule configured as "Delete files of type X", **When** executed, **Then** the file is moved to an internal quarantine folder (`Ghost_Clerk_Trash`), never immediately deleted from the file system.

---

## Edge Cases and Error Scenarios

* **Temporary Download Files:**
    * The system **MUST STRICTLY IGNORE** files with `.crdownload`, `.download`, `.part` extensions or hidden files starting with `.`. They are only processed when the browser renames them to their final extension.
* **OCR Failure / Low-Quality Images:**
    * If the `Vision` framework does not return text with sufficient confidence, it is treated as "Unclassifiable File" -> Review Tray.
* **Locked Files:**
    * If the file is locked by the system, it retries silently after an exponential wait (backoff) up to 3 times. If it persists, it is ignored until the next system event.
* **Lack of Permissions:**
    * If the system does not have write permissions in the destination folder (Sandbox), it must notify a critical error in the menu and pause automation.

---

## Key Technical Requirements (macOS Stack)

* **Absolute Privacy (Local First):** No network requests allowed for analysis.
* **Language & UI:** Swift 5+ and SwiftUI. Use of `MenuBarExtra` for the status interface.
* **AI / Inference:**
    * **Engine:** `MLX Swift` (Apple Silicon optimized) or `llama.cpp-swift`.
    * **Model:** `Phi-3.5-mini-instruct` (GGUF Q4_K_M).
* **Vision:** Native `Vision` framework (Class `VNRecognizeTextRequest`) for free and fast OCR.
* **File Monitoring:** Native `DispatchSource` or `FSEvents`.

---

## Success Criteria (The "Why")

* **"Out of the box" functionality:** The user can install the app, write a rule in plain English, and see it work in less than 2 minutes.
* **Zero Interruptions:** Installers (`.dmg`) never disappear from the user's view.
* **Trust:** Zero reports of data loss thanks to Hash verification before deleting duplicates.