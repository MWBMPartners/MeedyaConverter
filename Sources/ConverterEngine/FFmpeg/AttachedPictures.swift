// ============================================================================
// MeedyaConverter — AttachedPictures
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// WHY THIS FILE EXISTS
// --------------------
// A picture attached to a file — an album's cover art, a film's poster — is
// not a track. ffprobe reports it as a "video stream" with the `attached_pic`
// flag, and the two big containers store it differently:
//
//   * MP4 / MOV: ffmpeg's muxer writes an `attached_pic` stream as the `covr`
//     item, so mapping the stream with its flag intact is enough.
//   * Matroska: the picture is an ATTACHMENT (a file inside the file, with a
//     name and a MIME type). ffmpeg's demuxer turns it into an `attached_pic`
//     video stream — but ffmpeg's MATROSKA MUXER only writes streams that are
//     themselves attachments as attachments. Checked with ffmpeg 9.0.1 (28
//     Sept 2026) and in its source (`matroskaenc.c` tests only for
//     `AVMEDIA_TYPE_ATTACHMENT`): even a plain `ffmpeg -i in.mkv -map 0 -c
//     copy out.mkv` turns `cover.jpg` into a one-frame MJPEG video TRACK.
//
// So for a Matroska output the engine first copies each picture, byte for
// byte, out of the source into its temporary folder (`extractionArguments`),
// and the argument builder then attaches that file with `-attach`, under the
// picture's own name and MIME type, instead of mapping the stream. Reading
// the result back gives exactly what the source had: an attachment that
// ffprobe reports as an `attached_pic` stream with the same name.
//
// WHAT IT CANNOT DO
// -----------------
// * Only the full encode (`EncodingEngine.encode`) runs the copying step.
//   Paths that build one ffmpeg command and nothing else (a pipeline step,
//   the Shortcuts action, the quality preview) have no picture file, so the
//   picture is mapped as a stream — and in a Matroska output ffmpeg makes it
//   a picture track. The builder says so in `trackWritingNotes()`.
// * WebM cannot hold pictures or attachments at all; nothing is attached
//   there (ffmpeg's WebM muxer refuses the stream either way).
// * A picture in a format with no known MIME type (see `imageFormat`) is not
//   copied out; it is mapped as a stream, with a note.
// ============================================================================

import Foundation

// MARK: - AttachedPictureAttachment

/// One picture the argument builder writes as a Matroska attachment
/// (`-attach`) instead of mapping it as a stream.
public struct AttachedPictureAttachment: Sendable, Equatable {
    /// The picture's stream in the source (whole-file number).
    public let sourceStreamIndex: Int
    /// The copy of the picture the engine made (see `AttachedPictures`).
    public let file: URL
    /// The name the attachment gets: the source's own, or a conventional one.
    public let fileName: String
    /// The attachment's MIME type (`image/jpeg`).
    public let mimeType: String
}

// MARK: - AttachedPictures

/// The rules for keeping attached pictures (cover art) through a conversion.
public enum AttachedPictures {

    /// Whether ffmpeg can only keep a picture in `container` by attaching a
    /// copy of it (`-attach`) — Matroska, but not WebM, which has no
    /// attachments. MP4/MOV keep a mapped `attached_pic` stream as cover art
    /// by themselves.
    public static func needsAttachment(in container: ContainerFormat?) -> Bool {
        switch container {
        case .mkv, .mka, .mks, .mk3d: return true
        default: return false
        }
    }

    /// The file extension and MIME type for a picture in `codec` (ffprobe's
    /// codec name), or `nil` for a codec not known to be a still image.
    public static func imageFormat(forCodec codec: String?) -> (fileExtension: String, mimeType: String)? {
        switch codec?.lowercased() {
        case "mjpeg", "jpeg", "jpegls": return ("jpg", "image/jpeg")
        case "png", "apng": return ("png", "image/png")
        case "bmp": return ("bmp", "image/bmp")
        case "gif": return ("gif", "image/gif")
        case "webp": return ("webp", "image/webp")
        case "tiff": return ("tif", "image/tiff")
        default: return nil
        }
    }

    /// ffmpeg arguments that copy picture stream `streamIndex` of `input`
    /// into `output` unchanged (`-c copy`, one frame, raw image file). The
    /// copy is byte-identical to the picture inside the source (checked with
    /// ffmpeg 9.0.1 for a JPEG in Matroska and in M4A).
    public static func extractionArguments(input: URL, streamIndex: Int, output: URL) -> [String] {
        [
            "-y", "-nostdin", "-v", "error",
            "-i", input.path,
            "-map", StreamSpecifier.source(streamIndex),
            "-c", "copy", "-frames:v", "1",
            "-f", "image2", output.path
        ]
    }

    /// The name an attachment gets: the source's own (just the last path
    /// part, made safe), or — for a picture with none, such as MP4 cover
    /// art — `cover.<ext>`, the name Matroska's cover-art convention uses
    /// for the main cover, with the stream number added when more than one
    /// picture needs a made-up name.
    static func attachmentFileName(for stream: MediaStream, fileExtension: String, isOnlyUnnamed: Bool) -> String {
        if let given = stream.attachmentFileName?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty {
            return PathSanitizer.sanitizeFilenameComponent((given as NSString).lastPathComponent)
        }
        return isOnlyUnnamed ? "cover.\(fileExtension)" : "cover-\(stream.streamIndex).\(fileExtension)"
    }

    /// The MIME type an attachment gets: the source's own when it is an
    /// image type, otherwise the one for the picture's codec.
    static func attachmentMimeType(for stream: MediaStream, derived: String) -> String {
        if let given = stream.attachmentMimeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           given.hasPrefix("image/"), given.utf8.count <= 100 {
            return given
        }
        return derived
    }
}

// MARK: - Builder support

extension FFmpegArgumentBuilder {

    /// The attached pictures in `plan` that this output can only keep by
    /// attaching a copy (a Matroska output), with the file extension each
    /// copy should have. The engine copies these out of the source before
    /// building the command (`attachedPictureFiles`).
    public func attachedPicturesNeedingCopies() -> [(streamIndex: Int, fileExtension: String)] {
        guard AttachedPictures.needsAttachment(in: resolveContainerFormat()),
              let plan = makeOutputStreamPlan(), let sources = sourceStreamsByIndex else { return [] }
        return plan.entries.compactMap { entry in
            guard entry.inputIndex == 0, isAttachedPicture(entry, sources: sources),
                  let format = AttachedPictures.imageFormat(forCodec: sources[entry.sourceStreamIndex]?.codecName) else {
                return nil
            }
            return (entry.sourceStreamIndex, format.fileExtension)
        }
    }

    /// The pictures in `plan` that are written with `-attach` rather than
    /// mapped: those that need it (`attachedPicturesNeedingCopies`) AND have
    /// a copy in `attachedPictureFiles`. Any other picture stays in the plan
    /// and is mapped as a stream.
    func pictureAttachments(in plan: OutputStreamPlan) -> [AttachedPictureAttachment] {
        guard AttachedPictures.needsAttachment(in: resolveContainerFormat()),
              let sources = sourceStreamsByIndex else { return [] }
        let pictures = plan.entries.filter { $0.inputIndex == 0 && isAttachedPicture($0, sources: sources) }
        let unnamed = pictures.filter { sources[$0.sourceStreamIndex]?.attachmentFileName?.isEmpty ?? true }.count
        return pictures.compactMap { entry in
            guard let stream = sources[entry.sourceStreamIndex],
                  let file = attachedPictureFiles[entry.sourceStreamIndex],
                  let format = AttachedPictures.imageFormat(forCodec: stream.codecName) else {
                return nil
            }
            return AttachedPictureAttachment(
                sourceStreamIndex: entry.sourceStreamIndex,
                file: file,
                fileName: AttachedPictures.attachmentFileName(
                    for: stream, fileExtension: format.fileExtension, isOnlyUnnamed: unnamed <= 1
                ),
                mimeType: AttachedPictures.attachmentMimeType(for: stream, derived: format.mimeType)
            )
        }
    }

    /// `-attach` arguments for `attachments`, each with the `mimetype` and
    /// `filename` metadata Matroska attachments need (ffmpeg refuses an
    /// attachment with no MIME type). Streams made by `-attach` come after
    /// every mapped stream, so the first one's attachment-counted position
    /// is the number of attachments `plan` maps (fonts, for example).
    func attachArguments(_ attachments: [AttachedPictureAttachment], after plan: OutputStreamPlan) -> [String] {
        let mappedAttachments = plan.entries.filter { $0.streamType == .attachment }.count
        var args: [String] = []
        for (offset, attachment) in attachments.enumerated() {
            let specifier = "-metadata:s:t:\(mappedAttachments + offset)"
            args += ["-attach", attachment.file.path]
            args += [specifier, "mimetype=\(attachment.mimeType)", specifier, "filename=\(attachment.fileName)"]
        }
        return args
    }
}
