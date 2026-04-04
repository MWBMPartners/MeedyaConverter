# MeedyaConverter — Standing Tasks

> These tasks MUST be performed automatically after EVERY development prompt/action.
> Saved for Claude AI context continuity.
> Last updated: 2026-04-04

## Mandatory Post-Action Tasks

### 1. GitHub Issue Management

- Before starting work: create a GitHub Issue (or sub-issue) for the action being taken
- Use highly detailed descriptions with acceptance criteria
- Assign to the correct milestone/phase
- If implementation is incomplete, update issue status to "In Progress" with a progress comment
- Once complete, close the issue with a summary comment

### 1a. Acceptance Criteria Tracking

- **At every step/stage of work**, review the relevant GitHub Issue's acceptance criteria checklist
- **Tick each criteria item** (`- [x]`) as soon as it is verified complete
- Do this incrementally — not just at the end. Each commit/action should update the checkboxes
- If a criteria item is partially done, add a comment noting progress
- This applies to ALL issues, ALL phases, consistently — no exceptions
- Use `gh issue edit {number} --body` to update checkboxes, or `gh issue comment` for progress notes

### 2. Code Quality — Lint, Syntax & Structure

- Run thorough codebase checks for lint, syntax, and structural issues
- Resolve ALL issues regardless of severity (errors, warnings, notices, recommendations)
- Include pre-existing issues in modified files
- **Repeat checks until zero issues remain**

### 3. Security Audit

- Run thorough project security checks on all changed code
- Check for: command injection, path traversal, insecure file permissions, hardcoded secrets, dependency vulnerabilities
- Resolve all security gaps/vulnerabilities found
- **Repeat checks until zero issues remain**

### 4. Accessibility Compliance

- All UI code must be accessibility compliant
- VoiceOver support, keyboard navigation, Dynamic Type
- Proper accessibility labels and hints on all interactive elements

### 5. Documentation Updates — Markdown Files

- Thoroughly update ALL `.md` documents to ensure they are current:
  - README.md
  - CHANGELOG.md
  - PROJECT_STATUS.md
  - Project_Plan.md
  - DEV_NOTES.md (if exists)
  - help/*.md (all help documentation)

### 6. GitHub Updates

- Thoroughly update:
  - GitHub Issues (create new, update existing, close completed)
  - GitHub Milestones (update progress)
  - GitHub Project board (move cards)
  - GitHub Wiki (update relevant pages)

### 7. In-App Documentation

- Update all in-app help content in Resources/Help/
- Ensure help text matches current feature state

### 8. Gitignore Maintenance

- Maintain .gitignore suitably for this project
- Consider all dev environments: VSCode, Xcode, macOS, Windows, Raspberry Pi

### 9. Stage & Commit After Each Dev Step (No Push)

- After EACH dev step/task is actioned, STAGE changed files (`git add`) and COMMIT with a descriptive message
- Do this incrementally — not in a batch at the end. Each logical unit of work gets its own commit
- Commit messages should reference the task/issue number (e.g., "Phase 1.3: Integrate libmediainfo (#225)")
- Do NOT push — push is manual only. We will push when ready
- Never skip staging — all changes must be tracked

### 10. Cleanup

- Remove temporary development files
- Clean up any build artifacts not needed

### 11. CLI API Documentation (Swagger/OpenAPI)

- Update detailed Swagger/OpenAPI documentation for MeedyaConverter's CLI API after each task
- Document all CLI commands, options, arguments, exit codes, and JSON schemas
- Keep in sync with actual CLI implementation
- Store in `docs/api/` as OpenAPI YAML spec
- This ensures the CLI API documentation is always current and machine-readable

### 13. Claude Context Updates

- Update .claude/ memory, context, and prompt files
- Keep project brief current
- Update MEMORY.md in Claude's memory directory

## Code Standards (Apply to All Code)

- Detailed comments/annotations on every code block (not abbreviated)
- Proprietary copyright headers: `// (C) 2026–present MWBM Partners Ltd. All rights reserved.`
- Copyright year end should use `Calendar.current.component(.year, from: Date())` in code where dynamic
- Full code formatting (line breaks, indentation, readable structure)
- Modular architecture
- Swift 6.3 with strict concurrency checking

## Apple-Specific Standards

- Native Swift 6.3 / SwiftUI for macOS
- Meet App Store distribution guidelines where possible
- Explicitly call out any features that cannot meet App Store guidelines
- Code signing and notarization ready (paid Apple Developer Programme account)
- Dual distribution: App Store (sandboxed) + Direct (Sparkle updates)
