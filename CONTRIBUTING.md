# Contributing to GhostClerk

Thanks for your interest in contributing. These guidelines describe how to collaborate effectively and consistently.

## Code & Style
- SwiftUI first: prefer SwiftUI implementations; only use AppKit (`NSViewRepresentable`) when strictly necessary.
- Concurrency: use Swift Concurrency (`async/await`, `Task`, `actor`).
- Architecture: follow MVVM — keep Views as thin as possible and place business logic in Services/Managers.
- Error handling: do not fail silently; propagate errors with `throws` or `Result` and use the `Logger` API for important events.
- Follow the patterns described in `copilot-instructions.md` included in the repository.

## Commits
- Use clear commit messages (English preferred). Suggested prefixes:
  - `feat:` new feature
  - `fix:` bug fix
  - `docs:` documentation
  - `chore:` maintenance
- Write a concise description explaining *why* the change was made.

## Pull Requests
- Open PRs against `main`. Include:
  - A short summary of the change
  - Screenshots or logs when relevant
  - Notes about compatibility or migration if applicable
- Link related issues when available.

## Tests
- Add unit tests for complex logic (e.g., rule matching, hashing).
- Ensure existing tests pass before requesting review.

## Security & User Data
- Do not commit sensitive data.
- For persistent folder access, use `security-scoped bookmarks` (see `FileSystem/BookmarkManager.swift`).

## Code Review
- Keep changes small and focused.
- Respond to reviewer comments and update the PR accordingly.

If you have questions about architecture or need guidance on a task, open an issue or contact the maintainers.