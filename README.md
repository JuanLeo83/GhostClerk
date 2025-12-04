# GhostClerk

GhostClerk is a macOS menu bar agent that organizes local files using on-device LLMs via MLX Swift. It targets macOS 14+ (Sonoma) and is implemented with SwiftUI, following MVVM and Swift Concurrency patterns (`async/await`).

**Status:** In development

**Relevant files:**
- `spec.md` — Functional specification
- `plan.md` — High-level plan
- `task.md` — Development tasks and context

## Key goals
- Organize local files (for example `~/Downloads`) using configurable rules and local LLMs.
- Run as a background menu-bar agent (no Dock icon) using `MenuBarExtra` and `LSUIElement`.
- Use `mlx-swift` for quantized GGUF models and `Vision` for OCR where needed.

## Requirements
- macOS 14 (Sonoma) or later
- Xcode 15+
- Apple Silicon recommended for best performance with local models

## Open & Run
1. Open the project in Xcode:

```bash
open GhostClerk.xcodeproj
```

2. Select the `GhostClerk` scheme and run on your Mac (not a simulator).

Notes:
- The app runs as a menu-bar agent (no Dock icon). Inspect `GhostClerkApp.swift` and `GhostClerk/GhostClerk.entitlements` for related settings.
- For development requiring folder access, see `FileSystem/BookmarkManager.swift` for the `security-scoped bookmarks` logic.

## Repository structure (short)


## Development notes
- Follow conventions in `CONTRIBUTING.md`.
- Prefer SwiftUI; use AppKit only when strictly necessary.


- Run tests from Xcode or via `xcodebuild`.

## License
This project is licensed under the MIT License (see `LICENSE`).

## Maintainers / Contact
- Maintainer: `JuanLeo83` (repo owner)
