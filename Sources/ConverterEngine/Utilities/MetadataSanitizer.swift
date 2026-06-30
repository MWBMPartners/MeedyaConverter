// ============================================================================
// MeedyaConverter — MetadataSanitizer
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MetadataSanitizer

/// Helper for cleaning string values that come from media-file
/// metadata (ffprobe JSON output, ID3 tags, vorbis comments,
/// matroska tags) before they flow into the rest of the app.
///
/// **Why this exists** (SECURITY.md threat T5, finding F-006):
/// ffprobe's `format_tags` / `stream_tags` carry arbitrary bytes
/// from the source file. A user importing a crafted media file
/// has not yet been compromised — but the moment that file's
/// metadata renders inside the MeedyaConverter UI, terminal,
/// log file, or AppleScript bridge, embedded control characters
/// become an attack surface:
///
/// * **NUL bytes** terminate C-string filename APIs and confuse
///   the BSD POSIX layer; a NUL embedded in a title can split
///   the visible string from the actual stored bytes when the
///   metadata flows back through `URL` / filesystem.
/// * **ANSI / VT100 escape sequences** (anything starting with
///   `0x1B`) re-colour text, move the cursor, clear the screen
///   — when written to a terminal log they let a crafted title
///   forge fake error messages or hide legitimate output.
/// * **Other C0 control characters** (BS, DEL, etc.) variously
///   re-position the cursor or delete previously-rendered
///   characters; combined with VT100 they enable convincing
///   forgery.
/// * **Bidirectional override codepoints** (RLO `U+202E`, LRO
///   `U+202D`, etc.) flip text rendering direction — the
///   "Trojan Source" attack family. A filename like
///   `'innocent\u{202E}cod.exe'` displays as `'innocenttxe.doc'`
///   in most renderers.
///
/// Real media titles do not legitimately need any of these.
/// Sanitising at the parse boundary keeps downstream renderers
/// honest without any per-callsite change.
///
/// **What this does NOT do**: it does not enforce any length
/// limit (caller's choice), HTML-escape (renderers' job),
/// or strip whitespace (legitimate titles have spaces). It is a
/// purely additive defence against well-known forgery vectors.
public enum MetadataSanitizer {

    /// Sanitise a raw metadata string for display / logging /
    /// downstream propagation. Removes:
    ///
    /// 1. NUL bytes (`\0`, `U+0000`).
    /// 2. ASCII C0 control codes (`U+0001`–`U+001F`) **except**
    ///    TAB (`U+0009`), LF (`U+000A`), CR (`U+000D`). The
    ///    three exceptions are kept because some legitimate
    ///    metadata fields (long-form `comment`, song-lyrics
    ///    embedded as a tag) use them for line breaks.
    /// 3. DEL (`U+007F`).
    /// 4. Bidirectional-override Unicode codepoints (`U+202A`–
    ///    `U+202E`, `U+2066`–`U+2069`).
    ///
    /// Idempotent — re-sanitising a sanitised string returns
    /// the same string. Empty input returns empty output (no
    /// `"unnamed"` placeholder substitution; that's
    /// `PathSanitizer`'s job for a different reason).
    public static func sanitize(_ raw: String) -> String {
        var result = String()
        result.reserveCapacity(raw.count)

        for scalar in raw.unicodeScalars {
            let value = scalar.value
            switch value {
            case 0:
                continue
            case 0x01...0x08, 0x0B, 0x0C, 0x0E...0x1F:
                continue
            case 0x7F:
                continue
            case 0x202A...0x202E:
                continue
            case 0x2066...0x2069:
                continue
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }
}
