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
    /// 4. C1 control codes (`U+0080`–`U+009F`) — this range
    ///    includes NEL (`U+0085`, treated as a line break by
    ///    many renderers) and CSI (`U+009B`, the 8-bit ANSI
    ///    control-sequence introducer). None of these are ever
    ///    legitimately present in media metadata text, and
    ///    leaving them would undermine the ANSI/VT100
    ///    log-forgery defence this helper's own contract claims.
    /// 5. Unicode line/paragraph separators LS (`U+2028`) and
    ///    PS (`U+2029`) — rendered as hard line breaks by many
    ///    terminals, log viewers, and JS/Electron consoles, so
    ///    they enable the same fake-log-line forgery as a raw
    ///    newline. (Unlike LF/CR, they carry no legitimate
    ///    "the author typed a newline in a comment" meaning.)
    /// 6. Bidirectional-override Unicode codepoints (`U+202A`–
    ///    `U+202E`, `U+2066`–`U+2069`).
    ///
    /// Idempotent — re-sanitising a sanitised string returns
    /// the same string. Empty input returns empty output (no
    /// `"unnamed"` placeholder substitution; that's
    /// `PathSanitizer`'s job for a different reason).
    ///
    /// - Note: LF/CR are deliberately RETAINED here (multi-line
    ///   comment tags are legitimate). A single-line context that
    ///   must not contain ANY line break — e.g. the AppleScript
    ///   bridge's one-line `ERROR:` replies — should call
    ///   `sanitizeSingleLine(_:)` instead.
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
            case 0x80...0x9F:
                continue
            case 0x2028, 0x2029:
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

    /// Like `sanitize(_:)` but ALSO strips the newline-class
    /// characters that `sanitize` keeps (TAB, LF, CR), collapsing
    /// them to a single space. Use for any context that renders as
    /// a single logical line and must not be splittable by
    /// caller-controlled input — e.g. the AppleScript scripting
    /// bridge's `ERROR:` replies, where a retained LF would let a
    /// caller forge a second line in the consumer's log
    /// (SECURITY.md F-008 newline-injection follow-up).
    ///
    /// Runs `sanitize` first (so all control / bidi / line-separator
    /// stripping applies), then replaces any surviving TAB/LF/CR
    /// with a single space and coalesces runs of spaces so the
    /// result stays readable.
    public static func sanitizeSingleLine(_ raw: String) -> String {
        let base = sanitize(raw)
        var result = String()
        result.reserveCapacity(base.count)
        var lastWasSpace = false
        for scalar in base.unicodeScalars {
            let isBreak = scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
            if isBreak || scalar == " " {
                if !lastWasSpace {
                    result.unicodeScalars.append(" ")
                    lastWasSpace = true
                }
            } else {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return result
    }
}
