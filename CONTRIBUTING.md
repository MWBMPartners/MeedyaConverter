<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Contributing to MeedyaConverter

Thank you for your interest in contributing to MeedyaConverter — part of the
MeedyaSuite product family from [MWBM Partners Ltd](https://github.com/MWBMPartners).
This document describes the code standards, branch strategy, and PR process for
the project.

> **Please also read [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)** — the
> Contributor Covenant v2.1 applies to this project (and across the wider
> MeedyaSuite family).

## Licensing posture

MeedyaConverter is a **proprietary commercial product** owned by MWBM Partners
Ltd, released under the licence in [`LICENSE`](LICENSE). External
contributions are welcomed under the following terms:

- **You retain copyright** in the code you contribute.
- **You grant MWBM Partners Ltd a perpetual, worldwide, royalty-free,
  sublicensable, irrevocable licence** to use your contribution in any way,
  including incorporating it into the proprietary product, sublicensing it
  to downstream distributors, and combining it with other MWBM Partners
  software. By opening a pull request you accept these terms.
- **You warrant** that you have the right to make the contribution — i.e. it
  is your own original work, or you have explicit permission from the
  rights-holder to contribute it, and it doesn't infringe any third-party
  copyright, patent, trademark, or trade secret.
- **No CLA signing process is in place yet.** For now, the contribution
  itself (the PR commit and the merge accepting it) constitutes the
  agreement. A formal CLA may be introduced if/when contribution volume
  warrants it; that change would be announced and not retroactive.

If you can't accept these terms, please **don't open the PR**. We'd rather
have the conversation up front than have to back something out later.

For non-trivial contributions you may want to open a discussion issue
**before** writing the code, so we can confirm fit + approach.

## Security disclosures

Security issues — **please don't** open a public GitHub issue. Follow the
disclosure process in [`.github/SECURITY.md`](.github/SECURITY.md).

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

1. Clone the repository:

   ```bash
   git clone https://github.com/MWBMPartners/MeedyaConverter.git
   cd MeedyaConverter
   ```

2. Toolchain prerequisites:
   - **macOS 14+** (Sonoma) for development; **macOS 15+** (Sequoia) for
     full release-build feature parity (the build targets `.macOS(.v15)`
     in `Package.swift`).
   - **Swift 6.3+** — bundled with **Xcode 26.5+**.

3. Install FFmpeg via Homebrew for runtime testing:

   ```bash
   brew install ffmpeg
   ```

4. (Optional but recommended) Install SwiftLint via Homebrew for linting:

   ```bash
   brew install swiftlint
   ```

5. Open `Package.swift` in Xcode, or use VS Code with the official Swift
   extension (`swiftlang.swift-lang`).

6. Verify your setup builds and tests cleanly:

   ```bash
   swift build --configuration release
   swift test --parallel
   ```

For a deeper guide see [`docs/Getting-Started.md`](docs/Getting-Started.md).
For the in-app help index see [`Sources/MeedyaConverter/Resources/Help/`](Sources/MeedyaConverter/Resources/Help/).

---

## Reporting Issues

- Use the GitHub issue tracker.
- Include: steps to reproduce, expected vs. actual behaviour, macOS version, Swift version.
- Attach relevant logs or media file details (codec, container, resolution).
- Use the provided issue templates when available.
