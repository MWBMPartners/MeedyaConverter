<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Contributing

Thank you for your interest in contributing to MeedyaConverter. This document describes the code standards, branch strategy, and PR process for the project.

---

## Code Style

### Swift Version and Concurrency

- **Swift 6** language mode is enforced across all targets.
- **Strict concurrency** is enabled at the "complete" level.
- All types crossing concurrency boundaries must conform to `Sendable`.
- Use `@Sendable` for closures passed across isolation domains.
- Use `@Observable` (Observation framework) for view models, not `ObservableObject`/`@Published`.

### Naming and Formatting

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Use descriptive names. Avoid abbreviations unless widely understood (e.g., `URL`, `HDR`).
- Type names: `UpperCamelCase`.
- Properties, methods, variables: `lowerCamelCase`.
- Constants: `lowerCamelCase` (not `SCREAMING_SNAKE_CASE`).

### SwiftLint Configuration

The project includes a SwiftLint configuration (`.swiftlint.yml`) that enforces:

- Maximum line length (120 characters, warning at 150).
- Trailing whitespace removal.
- Consistent brace and parenthesis style.
- Force unwrap warnings.
- Unused import detection.
- `Sendable` conformance checks.

Run SwiftLint locally before submitting a PR:

```bash
swiftlint lint
```

If SwiftLint is installed via Homebrew, it runs automatically as part of the build process in Xcode.

### File Headers

Every Swift source file must include the proprietary copyright header:

```swift
// ============================================================================
// MeedyaConverter — <FileName>
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
```

The copyright year is always 2026 (project inception year). Do not change it to the current year.

### Documentation

- All public types, methods, and properties must have documentation comments (`///`).
- Use `// MARK: -` to organise sections within files.
- Inline comments should explain *why*, not *what*.
- Annotations should be detailed and descriptive -- this is a documented codebase.

### Access Control

- Default to the minimum required access level.
- `public` for API consumed by other modules (CLI, GUI importing ConverterEngine).
- `internal` for module-internal types (the default).
- `private` for implementation details within a file.

---

## Branch Strategy

MeedyaConverter uses a three-branch model:

| Branch | Purpose | Protection |
| ------ | ------- | ---------- |
| `main` | Production-ready code | Protected. Requires PR review. |
| `beta` | Integration testing | Semi-protected. |
| `alpha` | Active development | Development branch. |

### Workflow

1. Create a feature branch from `alpha` (or `main` for hotfixes).
2. Name branches descriptively: `feature/hls-manifest`, `fix/hdr-metadata-loss`, `docs/cli-reference`.
3. Open a PR targeting the appropriate base branch.
4. Never push directly to `main`.
5. Never force-push to any shared branch.

---

## Pull Request Process

### Before Submitting

1. **Build** passes: `swift build` succeeds with no errors.
2. **Tests** pass: `swift test` succeeds with no failures.
3. **No warnings**: resolve all compiler warnings, especially concurrency warnings.
4. **Lint**: run `swiftlint lint` and fix any violations. No trailing whitespace, consistent formatting.
5. **Documentation**: new public API has doc comments.

### PR Requirements

- Clear title describing the change (e.g., "Add HLS manifest generation" not "Update code").
- Description explaining *what* changed and *why*.
- Reference the GitHub issue number (e.g., "Closes #42").
- Keep PRs focused -- one feature or fix per PR.
- Include tests for new functionality.

### Review Process

- At least one approving review is required to merge into `main`.
- Reviewers check: correctness, Swift 6 compliance, documentation, test coverage.
- Address all review comments before merging.

---

## Commit Messages

Use clear, descriptive commit messages:

```text
<type>: <short summary>

<optional body explaining why>

Closes #<issue>
```

Types:

- `feat` -- New feature.
- `fix` -- Bug fix.
- `refactor` -- Code restructuring without behaviour change.
- `docs` -- Documentation only.
- `test` -- Adding or updating tests.
- `chore` -- Build, CI, dependency updates.

Examples:

```text
feat: Add HLS adaptive bitrate ladder generation

Implements multi-variant HLS output with configurable quality
tiers. Generates master playlist and per-variant playlists.

Closes #78
```

```text
fix: Preserve HDR10+ metadata during H.265 passthrough

The metadata sidecar was being dropped when the output container
differed from the input. Now correctly copies the JSON sidecar
file alongside the encoded output.

Closes #92
```

---

## Testing Requirements

- All new engine features must have corresponding unit tests in `Tests/ConverterEngineTests/`.
- CLI command tests go in `Tests/MeedyaConvertTests/`.
- Tests must pass in Swift 6 strict concurrency mode.
- Use descriptive test names: `testFFmpegArgumentBuilder_withHDR10Input_preservesMetadata()`.
- Mock external dependencies (FFmpeg, file system) where possible.
- Aim for meaningful coverage -- test edge cases, error paths, and boundary conditions.
- Integration tests that require FFmpeg should be gated behind a test flag so CI can run without FFmpeg installed.

---

## Development Setup

1. Clone the repository (see [Building from Source](Building-from-Source)).
2. Install FFmpeg via Homebrew for runtime testing.
3. Install SwiftLint via Homebrew for linting: `brew install swiftlint`.
4. Open `Package.swift` in Xcode or use VS Code with the Swift extension (`swiftlang.swift-lang`).
5. Run `swift build` and `swift test` to verify your setup.

---

## Reporting Issues

- Use the GitHub issue tracker.
- Include: steps to reproduce, expected vs. actual behaviour, macOS version, Swift version.
- Attach relevant logs or media file details (codec, container, resolution).
- Use the provided issue templates when available.
