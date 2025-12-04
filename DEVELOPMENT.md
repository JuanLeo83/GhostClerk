# Development Notes

This document captures local development notes and project-specific guidance.

## Open the project
- Open `GhostClerk.xcodeproj` in Xcode 15+.

## Running the app
- Run the `GhostClerk` scheme on a Mac.
- The app runs as a menu-bar agent (no Dock icon). Check `Info.plist` and `GhostClerk.entitlements` for configuration.

## Entitlements & Sandbox
- The app is designed to run in the App Sandbox. For persistent access to user folders, the project uses `security-scoped bookmarks` (see `FileSystem/BookmarkManager.swift`).

## MLX & local models
- MLX integration lives in `GhostClerk/AI/MLXWorker.swift`.
- Quantized GGUF models should be placed in a location configured by the user or installer. Document any default paths in `spec.md` if needed.

## Tests
- Run tests from Xcode or via:

```bash
xcodebuild test -scheme GhostClerk -workspace GhostClerk.xcodeproj -destination 'platform=macOS'
```

## Architecture notes
- Views: SwiftUI
- Logic: Services/Managers (e.g., `FileProcessor`, `FolderMonitor`, `ClerkFileManager`)
- OCR: `Vision/TextExtractor.swift`

## Local best practices
- Do not commit sensitive data or large model binaries.
- Use clear branch names: `feat/<description>`, `fix/<issue>`.

## Contact
- Lead maintainer: `JuanLeo83`.
