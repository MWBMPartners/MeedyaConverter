// ============================================================================
// MeedyaConverter — StreamMetadataEditor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - StreamMetadataEdit

/// A single metadata edit operation on a stream.
public struct StreamMetadataEdit: Codable, Sendable, Identifiable {
    public let id: UUID
    public var streamIndex: Int
    public var key: String
    public var value: String?

    public init(
        id: UUID = UUID(),
        streamIndex: Int,
        key: String,
        value: String? = nil
    ) {
        self.id = id
        self.streamIndex = streamIndex
        self.key = key
        self.value = value
    }
}

// MARK: - DispositionEdit

/// A disposition flag edit for a stream.
public struct DispositionEdit: Codable, Sendable {
    public var streamIndex: Int
    public var disposition: StreamDisposition

    public init(streamIndex: Int, disposition: StreamDisposition) {
        self.streamIndex = streamIndex
        self.disposition = disposition
    }
}

// MARK: - StreamDisposition

/// Standard FFmpeg stream disposition flags.
public struct StreamDisposition: Codable, Sendable, Equatable {
    public var isDefault: Bool
    public var isDub: Bool
    public var isOriginal: Bool
    public var isComment: Bool
    public var isLyrics: Bool
    public var isKaraoke: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool
    public var isVisualImpaired: Bool
    public var isCleanEffects: Bool
    public var isDescriptions: Bool

    public init(
        isDefault: Bool = false,
        isDub: Bool = false,
        isOriginal: Bool = false,
        isComment: Bool = false,
        isLyrics: Bool = false,
        isKaraoke: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isVisualImpaired: Bool = false,
        isCleanEffects: Bool = false,
        isDescriptions: Bool = false
    ) {
        self.isDefault = isDefault
        self.isDub = isDub
        self.isOriginal = isOriginal
        self.isComment = isComment
        self.isLyrics = isLyrics
        self.isKaraoke = isKaraoke
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isVisualImpaired = isVisualImpaired
        self.isCleanEffects = isCleanEffects
        self.isDescriptions = isDescriptions
    }

    /// FFmpeg disposition string (e.g., "default+forced").
    public var ffmpegValue: String {
        var flags: [String] = []
        if isDefault { flags.append("default") }
        if isDub { flags.append("dub") }
        if isOriginal { flags.append("original") }
        if isComment { flags.append("comment") }
        if isLyrics { flags.append("lyrics") }
        if isKaraoke { flags.append("karaoke") }
        if isForced { flags.append("forced") }
        if isHearingImpaired { flags.append("hearing_impaired") }
        if isVisualImpaired { flags.append("visual_impaired") }
        if isCleanEffects { flags.append("clean_effects") }
        if isDescriptions { flags.append("descriptions") }
        return flags.isEmpty ? "0" : flags.joined(separator: "+")
    }

    /// Parse from FFmpeg disposition string.
    public static func parse(_ value: String) -> StreamDisposition {
        let lower = value.lowercased()
        return StreamDisposition(
            isDefault: lower.contains("default"),
            isDub: lower.contains("dub"),
            isOriginal: lower.contains("original"),
            isComment: lower.contains("comment"),
            isLyrics: lower.contains("lyrics"),
            isKaraoke: lower.contains("karaoke"),
            isForced: lower.contains("forced"),
            isHearingImpaired: lower.contains("hearing_impaired"),
            isVisualImpaired: lower.contains("visual_impaired"),
            isCleanEffects: lower.contains("clean_effects"),
            isDescriptions: lower.contains("descriptions")
        )
    }
}

// MARK: - StreamMetadataEditSet

/// A collection of metadata edits to apply during encoding.
public struct StreamMetadataEditSet: Codable, Sendable {
    /// Global (file-level) metadata edits.
    public var globalEdits: [String: String?]

    /// Per-stream metadata edits.
    public var streamEdits: [StreamMetadataEdit]

    /// Per-stream disposition edits.
    public var dispositionEdits: [DispositionEdit]

    public init(
        globalEdits: [String: String?] = [:],
        streamEdits: [StreamMetadataEdit] = [],
        dispositionEdits: [DispositionEdit] = []
    ) {
        self.globalEdits = globalEdits
        self.streamEdits = streamEdits
        self.dispositionEdits = dispositionEdits
    }

    /// Whether any edits are pending.
    public var hasEdits: Bool {
        !globalEdits.isEmpty || !streamEdits.isEmpty || !dispositionEdits.isEmpty
    }
}

// MARK: - StreamMetadataEditor

/// Builds FFmpeg arguments for editing stream and file-level metadata.
///
/// Enables per-stream title, language, and disposition editing during
/// transcoding or remuxing. Supports both setting and clearing metadata fields.
///
/// Phase 3.6
public struct StreamMetadataEditor: Sendable {

    /// Common metadata keys for streams.
    public enum CommonKey: String, CaseIterable, Sendable {
        case title = "title"
        case language = "language"
        case handler = "handler_name"
        case encoder = "encoder"
        case comment = "comment"
        case artist = "artist"
        case album = "album"
        case genre = "genre"
        case date = "date"
        case track = "track"
        case copyright = "copyright"
    }

    // MARK: - Argument Building

    /// Build FFmpeg arguments from a metadata edit set.
    ///
    /// - Parameter editSet: The collection of edits to apply.
    /// - Returns: FFmpeg argument array.
    public static func buildArguments(
        from editSet: StreamMetadataEditSet
    ) -> [String] {
        var args: [String] = []

        // Global metadata edits
        for (key, value) in editSet.globalEdits.sorted(by: { $0.key < $1.key }) {
            if let val = value {
                args += ["-metadata", "\(key)=\(val)"]
            } else {
                // Setting to empty string clears the key
                args += ["-metadata", "\(key)="]
            }
        }

        // Per-stream metadata edits
        for edit in editSet.streamEdits {
            if let value = edit.value {
                args += ["-metadata:s:\(edit.streamIndex)", "\(edit.key)=\(value)"]
            } else {
                args += ["-metadata:s:\(edit.streamIndex)", "\(edit.key)="]
            }
        }

        // Disposition edits
        for edit in editSet.dispositionEdits {
            args += ["-disposition:\(edit.streamIndex)", edit.disposition.ffmpegValue]
        }

        return args
    }

    /// Build FFmpeg arguments to set a stream's title.
    ///
    /// - Parameters:
    ///   - streamIndex: Stream index.
    ///   - title: New title (nil to clear).
    /// - Returns: FFmpeg argument array.
    public static func buildSetTitle(
        streamIndex: Int,
        title: String?
    ) -> [String] {
        return ["-metadata:s:\(streamIndex)", "title=\(title ?? "")"]
    }

    /// Build FFmpeg arguments to set a stream's language.
    ///
    /// - Parameters:
    ///   - streamIndex: Stream index.
    ///   - language: BCP 47 / ISO 639 language code (e.g., "eng", "fra", "deu").
    /// - Returns: FFmpeg argument array.
    public static func buildSetLanguage(
        streamIndex: Int,
        language: String
    ) -> [String] {
        return ["-metadata:s:\(streamIndex)", "language=\(language)"]
    }

    /// Build FFmpeg arguments to set stream disposition.
    ///
    /// - Parameters:
    ///   - streamIndex: Stream index.
    ///   - disposition: Disposition flags.
    /// - Returns: FFmpeg argument array.
    public static func buildSetDisposition(
        streamIndex: Int,
        disposition: StreamDisposition
    ) -> [String] {
        return ["-disposition:\(streamIndex)", disposition.ffmpegValue]
    }

    /// Build FFmpeg arguments to set the global title.
    ///
    /// - Parameter title: File title (nil to clear).
    /// - Returns: FFmpeg argument array.
    public static func buildSetGlobalTitle(
        title: String?
    ) -> [String] {
        return ["-metadata", "title=\(title ?? "")"]
    }

    /// Build FFmpeg arguments for a remux-only metadata edit (no re-encoding).
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output file.
    ///   - editSet: Metadata edits to apply.
    /// - Returns: Complete FFmpeg argument array.
    public static func buildRemuxEditArguments(
        inputPath: String,
        outputPath: String,
        editSet: StreamMetadataEditSet
    ) -> [String] {
        var args = [
            "-i", inputPath,
            "-map", "0",
            "-c", "copy",
        ]

        args += buildArguments(from: editSet)

        args += ["-y", outputPath]
        return args
    }

    // MARK: - Language Codes

    /// Common ISO 639-2/B language codes used in media files.
    public static let commonLanguages: [(code: String, name: String)] = [
        ("eng", "English"),
        ("fra", "French"),
        ("deu", "German"),
        ("spa", "Spanish"),
        ("ita", "Italian"),
        ("por", "Portuguese"),
        ("rus", "Russian"),
        ("jpn", "Japanese"),
        ("kor", "Korean"),
        ("zho", "Chinese"),
        ("ara", "Arabic"),
        ("hin", "Hindi"),
        ("nld", "Dutch"),
        ("swe", "Swedish"),
        ("nor", "Norwegian"),
        ("dan", "Danish"),
        ("fin", "Finnish"),
        ("pol", "Polish"),
        ("tur", "Turkish"),
        ("tha", "Thai"),
        ("vie", "Vietnamese"),
        ("und", "Undetermined"),
    ]

    /// Validate an ISO 639 language code.
    ///
    /// - Parameter code: Language code to validate.
    /// - Returns: `true` if the code is 2 or 3 lowercase letters.
    public static func isValidLanguageCode(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespaces).lowercased()
        return (trimmed.count == 2 || trimmed.count == 3) &&
               trimmed.allSatisfy(\.isLetter)
    }
}
