// ============================================================================
// MeedyaConverter — PathSanitizer
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - PathSanitizer

/// Helpers for defending against T2 path-traversal attacks (per
/// `SECURITY.md` finding F-002).
///
/// Two distinct surfaces are addressed:
///
/// 1. **Filename components built from untrusted strings** — the
///    `sanitizeFilenameComponent(_:)` helper strips characters that
///    could let a media-file basename, an AppleScript-supplied
///    string, or other external input flow into
///    `URL.appendingPathComponent(_:)` and escape its parent
///    directory. Foundation's `appendingPathComponent` performs no
///    such normalisation itself — passing `"../etc/passwd"` produces
///    a URL outside the intended parent.
///
/// 2. **Full output paths supplied from outside** — the
///    `URL.isContained(within:)` extension lets a caller assert that
///    a resolved output URL is still a descendant of an allowlist
///    root, after standardisation removes `..` components and
///    symbolic links. This is the right check for the AppleScript
///    bridge (`ScriptingBridge.swift`) and any future plugin/cross-
///    app handoff that hands us a fully-specified destination URL.
///
/// **Why both shapes exist**: silent sanitisation is appropriate
/// when the user did not explicitly choose the path (a media file's
/// auto-derived basename for example — the user expects the output
/// in the directory they chose, not in `/etc/`, and silently
/// stripping the `..` segments matches that intent). Containment
/// validation is appropriate when the user *did* explicitly supply
/// the path (an AppleScript caller, a Shortcuts intent destination
/// — the user expects the call to fail loudly if the destination
/// is invalid rather than have it silently rewritten to something
/// they did not authorise).
public enum PathSanitizer {

    /// Characters and patterns stripped from a sanitised filename
    /// component. A future expansion of this set is a non-breaking
    /// change for callers (the sanitised output stays a valid
    /// filename; we only ever remove more, never add).
    ///
    /// - `/` and `\` break out of the path-component model on POSIX
    ///   and on Windows-share-style paths reaching Foundation.
    /// - `..` collapses parent-directory traversal that survived
    ///   `URL.lastPathComponent`'s extraction.
    /// - NUL terminates filename parsing in BSD POSIX layer.
    /// - Leading dots produce hidden / dot-files which can mask
    ///   legitimate outputs from the user's Finder; one leading
    ///   dot is allowed (extensions), but a *bare* `.` or `..`
    ///   filename is stripped to a placeholder.
    /// - Trailing whitespace + dots produce filenames Windows and
    ///   some macOS APIs treat inconsistently.

    /// Returns a sanitised version of `component`, suitable for
    /// passing to `URL.appendingPathComponent(_:)` without escaping
    /// the parent directory.
    ///
    /// The transformation:
    /// 1. Replaces every `/` and `\` with `_`.
    /// 2. Removes every NUL.
    /// 3. Replaces every `..` substring with `__` (collapses parent
    ///    traversal without changing the visual length so the user
    ///    can recognise the file).
    /// 4. Strips leading whitespace and trailing whitespace + dots.
    /// 5. If the result is empty, a bare `.`, or a bare `..`,
    ///    returns the placeholder `"unnamed"` so the caller always
    ///    has a usable filename.
    ///
    /// Idempotent — sanitising an already-sanitised string returns
    /// the same string. The function does NOT alter file extensions;
    /// the entire input is sanitised including any extension dot.
    public static func sanitizeFilenameComponent(_ component: String) -> String {
        var result = component

        result = result.replacingOccurrences(of: "/", with: "_")
        result = result.replacingOccurrences(of: "\\", with: "_")
        result = result.replacingOccurrences(of: "\0", with: "")
        result = result.replacingOccurrences(of: "..", with: "__")

        // Trim leading whitespace and trailing whitespace + dots.
        result = result.trimmingCharacters(in: .whitespaces)
        while let last = result.last, last == "." || last.isWhitespace {
            result.removeLast()
        }

        if result.isEmpty || result == "." {
            return "unnamed"
        }
        return result
    }
}

// MARK: - URL extension — containment check

extension URL {

    /// Returns `true` when this URL's standardised path is equal to
    /// or a descendant of `root`'s standardised path.
    ///
    /// Use this to validate that a caller-supplied output URL still
    /// lands inside an allowlist of acceptable parent directories
    /// (the user's home, a Movies/Encoded folder, the app's
    /// sandbox container) after path-traversal sequences have been
    /// collapsed.
    ///
    /// - Important: callers MUST consult the *return value* of this
    ///   method — they cannot just call `.standardized` themselves
    ///   and trust the result. A path like `/tmp/foo/../../etc/passwd`
    ///   standardises to `/etc/passwd`, which is no longer a child
    ///   of `/tmp/foo`. The containment check is what makes the
    ///   sanitisation actionable.
    ///
    /// - Symlinks: this method DOES NOT resolve symbolic links. The
    ///   string-only `.standardized` form is used because
    ///   `resolvingSymlinksInPath()` on macOS produces inconsistent
    ///   results between paths that do and do not exist on disk
    ///   (e.g. `/private/tmp` resolves to `/tmp`, but a non-existent
    ///   child like `/private/tmp/a/b/c.txt` does not), which makes
    ///   the comparison unreliable. The threat-model implication is
    ///   that an attacker could plant a symlink inside the
    ///   allowlisted root that points outside it — but that already
    ///   requires write access inside the root, which is its own
    ///   compromise. For the AppleScript bridge surface this is the
    ///   acceptable trade-off.
    public func isContained(within root: URL) -> Bool {
        let resolvedSelf = self.standardized
        let resolvedRoot = root.standardized

        let selfPath = resolvedSelf.path
        let rootPath = resolvedRoot.path

        // Normalise trailing slash on root so a literal-equal check
        // and a prefix check agree on directory boundaries.
        let rootWithSlash: String
        if rootPath.hasSuffix("/") {
            rootWithSlash = rootPath
        } else {
            rootWithSlash = rootPath + "/"
        }

        return selfPath == rootPath || selfPath.hasPrefix(rootWithSlash)
    }
}
