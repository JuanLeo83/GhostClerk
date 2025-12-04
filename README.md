# GhostClerk 👻

Your intelligent, private file organizer for macOS.

![Banner](docs/images/banner_placeholder.png)

GhostClerk quietly lives in your menu bar and uses powerful on-device AI to automatically sort, rename, and organize your files. No cloud. No subscriptions. Just local productivity.

**Status:** In development

**Relevant files:** `spec.md`, `plan.md`, `task.md`

## Why GhostClerk?
- Local intelligence with MLX Swift — your data never leaves your Mac.
- Smart sorting beyond file extensions — understands content and context.
- OCR-powered classification — reads text inside images and PDFs.
- Optimized for Apple Silicon — fast, efficient on M1/M2/M3.
- Unobtrusive — menu bar agent with no Dock icon.

## Requirements
- macOS 14 (Sonoma) or later
- Xcode 15+
- Apple Silicon recommended for best performance with local models

## Install me

GhostClerk is currently in active development. Want to try it?

### Developer install
1. Open the project in Xcode:

```bash
open GhostClerk.xcodeproj
```

2. Select the `GhostClerk` scheme and run on your Mac (Target: My Mac).

Notes:
- The app runs as a menu-bar agent (no Dock icon). See `GhostClerkApp.swift` and `GhostClerk/GhostClerk.entitlements`.
- For folder access during development, check `FileSystem/BookmarkManager.swift` for `security-scoped bookmarks`.

## Screenshots

| Menu Bar | Settings |
|----------|----------|
| ![Menu Bar](docs/images/menubar_placeholder.png) | ![Settings](docs/images/settings_placeholder.png) |

## Development notes
- Follow conventions in `CONTRIBUTING.md`.
- Prefer SwiftUI; use AppKit only when strictly necessary.
- Use `async/await` and `Task` for asynchronous work; avoid raw GCD unless required for low-level APIs.

## License
This project is licensed under the MIT License (see `LICENSE`).

## Maintainers / Contact
- Maintainer: `JuanLeo83` (repo owner)
