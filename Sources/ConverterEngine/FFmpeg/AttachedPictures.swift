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
// flag, and what ffmpeg's writers do with such a stream depends entirely on
// the file type. Checked with ffmpeg 9.0.1 on 28 Sept 2026, mapping a JPEG
// cover as a copied stream with its flag kept (`TrackPreservationToolTests`
// re-checks the important ones against whatever ffmpeg the test machine has):
//
//   * MP4, M4A, M4V, M4B (and FLAC, MP3): kept as cover art (`covr`) — but
//     MP4's writer takes only JPEG, PNG or BMP cover art (`codec_cover_image_tags`
//     in ffmpeg's `movenc.c`): a GIF, TIFF or WebP cover makes it refuse the
//     WHOLE job ("Could not find tag for codec gif … not currently supported
//     in container", exit 234).
//   * Matroska (MKV, MKA, MKS, MK3D): the picture is an ATTACHMENT — a file
//     inside the file, with a name, a MIME type and a description. ffmpeg's
//     demuxer turns it into an `attached_pic` video stream, but its MATROSKA
//     MUXER only writes streams that are themselves attachments as
//     attachments (`matroskaenc.c` tests only for `AVMEDIA_TYPE_ATTACHMENT`):
//     even `ffmpeg -i in.mkv -map 0 -c copy out.mkv` turns `cover.jpg` into
//     a one-frame MJPEG video TRACK.
//   * MOV, 3GP, 3G2, AIFF: the job succeeds and the picture silently
//     disappears.
//   * MPEG-TS: it becomes a `bin_data` data stream. MPEG-PS: an "unknown"
//     video stream. AVI: a plain MJPEG video track.
//   * WebM, Ogg, FLV, CAF, W64, WAV/RF64, ADTS: ffmpeg refuses the whole
//     job ("Only VP8 or VP9 or AV1 video and Vorbis or Opus audio and WebVTT
//     subtitles are supported for WebM" and the like). MXF refuses it too
//     (it allows exactly one video stream). HLS writes MPEG-TS segments.
//     DASH and DCP were not checked; neither has a place for cover art.
//
// So, per file type (`pictureSupport`):
//
//   * MP4 family: a JPEG, PNG or BMP picture is mapped, with its flag, and
//     stays cover art; a picture in any other format is left out, with a
//     note (`mp4CoverArtCodecs`). Until the third independent review of the
//     language policy work, every picture was mapped, so a GIF or TIFF cover
//     made an MP4 job fail.
//   * Matroska: the engine first copies each picture, byte for byte, out of
//     the source into its temporary folder (`extractionArguments`,
//     `copyPictures`), and the argument builder ATTACHES that file with
//     `-attach`, under the picture's own name, MIME type and description,
//     instead of mapping the stream. Reading the result back gives exactly
//     what the source had.
//   * Everything else: the picture is taken OUT of the output entirely —
//     never mapped, so it can neither fail the job nor turn into a stray
//     track — and the job's notes say so (`trackWritingNotes`). Until the
//     language policy's third review round it was mapped anyway: WebM jobs
//     with cover art failed, and TS/AVI gained a mangled extra stream.
//   * An output with no video at all (`-vn`, the audio-only profiles):
//     ffmpeg drops a MAPPED picture along with the video, so it is left out
//     and noted too. A Matroska output keeps it, because it is attached, not
//     mapped.
//
// OTHER ATTACHMENTS
// -----------------
// A Matroska file can also carry files that are not cover art: fonts for
// styled subtitles, above all — and pictures that ffmpeg's Matroska reader
// does NOT turn into cover art. It does that only for some image types (JPEG,
// PNG, GIF, TIFF in ffmpeg 9.0.1); a BMP or WebP attachment stays a plain
// ATTACHMENT stream, with no codec. Only Matroska can hold attachments
// (`holdsAttachments`). With "map all streams", every attachment used to be
// mapped whatever the output, and ffmpeg refused the WHOLE job for MP4, M4V,
// M4A and MOV ("Could not find tag for codec none … not currently supported
// in container", exit 234), turned a font into a `bin_data` stream in
// MPEG-TS, and left it out of WebM without a word — found in the fourth
// independent review of the language policy work (WebM checked by hand with
// ffmpeg 9.0.1: VP9 and Opus with a font mapped, the job succeeds and the
// font is simply not there). Now an attachment is never mapped into a file type
// that cannot hold it, and is left out with a note — with or without "map
// all streams" (without it, attachments were already not mapped, but they
// went without a word). A Matroska output is unchanged: with "map all
// streams" its attachments are copied; without it they are still not chosen
// (issue #540).
//
// When the video is RE-ENCODED, a picture that is mapped (MP4) is copied,
// never re-encoded, and the video filters are aimed at the real video only
// (`pictureCopyArguments`, `videoFilterArguments`).
//
// WHAT IT CANNOT DO
// -----------------
// * A Matroska output can only keep a picture if a copy of it was made. The
//   full encode, a pipeline's encode step, the Shortcuts action and the
//   quality preview all make the copies, with ONE function
//   (`copyPictures`); a caller that builds a command without them gets the
//   picture LEFT OUT, with a note — never a one-frame picture track (which
//   the round-2 build produced on those three paths).
// * A picture in a format with no known MIME type (see `imageFormat`) cannot
//   be attached; it is left out of a Matroska output, with a note.
// * With no file type given (`ContainerFormat` nil — only possible when the
//   builder is used directly) nothing was checked: the picture is mapped as
//   it always was, unless the output has no video.
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
    /// The attachment's description (Matroska's `FileDescription`, which
    /// ffmpeg reads and writes as the stream's `title`) — the source's own,
    /// or the one set in the stream editor — or `nil` for none.
    public let description: String?
}

// MARK: - AttachedPictures

/// The rules for keeping attached pictures (cover art) through a conversion.
public enum AttachedPictures {

    /// What ffmpeg's writer does with a picture in a given file type (see the
    /// file header for what was checked).
    public enum PictureSupport: Sendable, Equatable {
        /// A picture mapped as a stream stays cover art (the MP4 family).
        case mappedAsCoverArt
        /// A picture can only be kept as an attachment (Matroska): the engine
        /// attaches a copy of it.
        case attachment
        /// ffmpeg cannot write a picture into this file type: it would refuse
        /// the job, drop the picture silently, or turn it into another kind
        /// of stream. The picture is left out, with a note.
        case none
        /// No file type is known, so nothing was checked: the picture is
        /// mapped as it always was.
        case unchecked
    }

    /// Why a picture — or another attached file — is not in the output.
    /// Each is reported, in plain English, in the job's notes
    /// (`FFmpegArgumentBuilder.trackWritingNotes`).
    public enum LeftOutReason: Sendable, Equatable {
        /// ffmpeg cannot write a picture into this file type.
        case fileTypeCannotHoldPictures(ContainerFormat)
        /// The output has no video (`-vn`), and ffmpeg drops a mapped picture
        /// with the video.
        case outputHasNoVideo
        /// A Matroska output needs a copy of the picture to attach, and none
        /// was made (the copying step failed, or the caller built the command
        /// without running it).
        case noCopyToAttach
        /// A Matroska output, and the picture's format (ffprobe's codec name)
        /// has no known file type to attach it as.
        case unknownPictureFormat(String?)
        /// An MP4-family output, and the picture is not JPEG, PNG or BMP —
        /// the only cover art ffmpeg's MP4 writer takes (`mp4CoverArtCodecs`).
        case notMP4CoverArtFormat(codec: String?, container: ContainerFormat)
        /// An ATTACHMENT stream — a font, or a picture ffmpeg reads as a plain
        /// attachment (BMP, WebP …) — and an output that is not Matroska,
        /// which cannot hold attachments (`holdsAttachments`). The source's
        /// file name and MIME type, when it gives them, name it in the note.
        case attachmentNotHeld(container: ContainerFormat, fileName: String?, mimeType: String?)
    }

    /// The picture formats (ffprobe's codec names) ffmpeg's MP4 writer takes
    /// as cover art: JPEG (`mjpeg`), PNG and BMP — `codec_cover_image_tags`
    /// in ffmpeg's `movenc.c` (checked in 9.0.1's source, and by
    /// `TrackPreservationToolTests`: a GIF or TIFF cover made it refuse the
    /// whole job). Any other picture is left out of an MP4-family output.
    static let mp4CoverArtCodecs: Set<String> = ["mjpeg", "png", "bmp"]

    /// A picture format's everyday name for a note (`GIF`, `TIFF`), from
    /// ffprobe's codec name.
    static func pictureFormatName(forCodec codec: String?) -> String {
        switch codec?.lowercased() {
        case "gif": return "GIF"
        case "tiff": return "TIFF"
        case "webp": return "WebP"
        case "jpegls": return "JPEG-LS"
        case "apng": return "animated PNG"
        case let other?: return other.uppercased()
        case nil: return "an unknown format"
        }
    }

    /// What ffmpeg's writer does with a picture in `container` (see the file
    /// header for what was checked, and with what).
    public static func pictureSupport(in container: ContainerFormat?) -> PictureSupport {
        guard let container else { return .unchecked }
        switch container {
        case .mp4, .m4v, .m4a, .m4b, .m4p:
            return .mappedAsCoverArt
        case .mkv, .mka, .mks, .mk3d:
            return .attachment
        case .mov, .webm, .mpegTS, .mpegPS, .mxf, .avi, .flv, .threeGP, .threeG2,
             .ogg, .ogm, .hls, .dash, .aiff, .caf, .w64, .rf64, .dcp:
            // Checked with ffmpeg 9.0.1: refused (WebM, Ogg, FLV, CAF, W64,
            // WAV/RF64, MXF), dropped silently (MOV, 3GP, 3G2, AIFF) or
            // turned into another kind of stream (MPEG-TS and HLS's MPEG-TS
            // segments `bin_data`, MPEG-PS "unknown" video, AVI an MJPEG
            // track). DASH and DCP were not checked; neither has a place for
            // cover art, so leaving it out cannot make a job fail.
            return .none
        }
    }

    /// Whether ffmpeg can only keep a picture in `container` by attaching a
    /// copy of it (`-attach`) — Matroska. MP4 keeps a mapped picture by
    /// itself; the rest cannot keep one at all.
    public static func needsAttachment(in container: ContainerFormat?) -> Bool {
        pictureSupport(in: container) == .attachment
    }

    /// Whether `container` can hold an ATTACHMENT stream (a font, or a
    /// picture ffmpeg reads as a plain attachment): only Matroska (MKV, MKA,
    /// MKS, MK3D). Everything else refuses the job, turns it into another
    /// kind of stream, or drops it without a word — WebM included (see the
    /// file header). `nil`
    /// when no file type is known: nothing was checked, and attachments are
    /// mapped as they always were.
    public static func holdsAttachments(in container: ContainerFormat?) -> Bool? {
        guard let container else { return nil }
        return pictureSupport(in: container) == .attachment
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

    /// The plain-English line for the job's notes saying that picture
    /// `streamIndex` is left out, and why.
    static func leftOutNote(streamIndex: Int, reason: LeftOutReason) -> String {
        let picture = "Stream #\(streamIndex) is a picture attached to the file (cover art)."
        switch reason {
        case .fileTypeCannotHoldPictures(let container):
            return "\(picture) ffmpeg cannot write pictures into this file type (\(container.displayName)), "
                + "so it is left out."
        case .outputHasNoVideo:
            return "\(picture) This output has no video, and ffmpeg drops pictures along with the video, "
                + "so it is left out."
        case .noCopyToAttach:
            return "\(picture) A Matroska file can only keep it as an attachment, and it could not be "
                + "copied out of the source to attach, so it is left out."
        case .unknownPictureFormat(let codec):
            return "\(picture) Its picture format (\(codec ?? "unknown")) is not one MeedyaConverter can "
                + "attach to a Matroska file, so it is left out."
        case .notMP4CoverArtFormat(let codec, let container):
            return "\(picture) ffmpeg can only write JPEG, PNG or BMP cover art into \(container.displayName) files, "
                + "and this picture is \(pictureFormatName(forCodec: codec)), so it is left out."
        case .attachmentNotHeld(let container, let fileName, let mimeType):
            return "Stream #\(streamIndex) is " + attachmentWords(fileName: fileName, mimeType: mimeType)
                + " Only a Matroska file can hold attachments, so it is left out of this \(container.displayName) file."
        }
    }

    /// ONE line for every attachment left out of a file type that is not
    /// Matroska (`LeftOutReason.attachmentNotHeld`), or `nil` when there are
    /// none: a single attachment as `leftOutNote` says it; several listed in
    /// one line. Until the stand-in review of round 5 each had its own line,
    /// so a release with 30 fonts gave 30 near-identical lines in the log.
    static func attachmentsLeftOutNote(
        _ attachments: [(streamIndex: Int, fileName: String?, mimeType: String?)],
        container: ContainerFormat
    ) -> String? {
        guard let first = attachments.first else { return nil }
        guard attachments.count > 1 else {
            return leftOutNote(streamIndex: first.streamIndex, reason: .attachmentNotHeld(
                container: container, fileName: first.fileName, mimeType: first.mimeType
            ))
        }
        let list = attachments.map {
            "stream #\($0.streamIndex), " + attachmentWords(fileName: $0.fileName, mimeType: $0.mimeType).dropLast()
        }
        return "Only a Matroska file can hold attachments, so these \(attachments.count) are left out of this "
            + "\(container.displayName) file: " + list.joined(separator: "; ") + "."
    }

    /// What an attachment stream is, in words for a note, ending in a full
    /// stop: "a font attached to the file (“f.ttf”, font/ttf)." or "a picture
    /// attached to the file (“c.bmp”, image/bmp) that ffmpeg reads as a
    /// plain attachment, not as cover art." The name and type come from the
    /// source (the probe sanitises them); a long name is shortened.
    static func attachmentWords(fileName: String?, mimeType: String?) -> String {
        let name = fileName.map { String(($0 as NSString).lastPathComponent.prefix(100)) }.flatMap { $0.isEmpty ? nil : $0 }
        let type = mimeType.map { String($0.prefix(100)).lowercased() }.flatMap { $0.isEmpty ? nil : $0 }
        let named = [name.map { "“\($0)”" }, type].compactMap { $0 }
        let given = named.isEmpty ? "" : " (\(named.joined(separator: ", ")))"
        let fileExtension = name.map { ($0 as NSString).pathExtension.lowercased() } ?? ""
        if type?.hasPrefix("image/") == true {
            return "a picture attached to the file\(given) that ffmpeg reads as a plain attachment, not as cover art."
        }
        let fontWords = ["font", "truetype", "opentype"]
        if fontWords.contains(where: { type?.contains($0) == true })
            || ["ttf", "otf", "ttc", "woff", "woff2"].contains(fileExtension) {
            return "a font attached to the file\(given)."
        }
        return "an attached file\(given)."
    }
}

// MARK: - Builder support

extension FFmpegArgumentBuilder {

    /// What happens to each attached picture (cover art) of an output: which
    /// are attached as Matroska attachments, which are left out and why, and
    /// the output plan without both. Worked out ONCE, by `pictureDecisions`,
    /// and used by the command (`build`), the notes (`trackWritingNotes`) and
    /// the copying step (`attachedPicturesNeedingCopies`), so they can never
    /// disagree.
    struct PictureDecisions {
        /// The output plan with the attached and the left-out pictures taken
        /// out — what is actually mapped.
        let plan: OutputStreamPlan
        /// The pictures written with `-attach`.
        let attachments: [AttachedPictureAttachment]
        /// The pictures — and other attachments (fonts …) — left out of the
        /// output, with the reason for each.
        let leftOut: [(sourceStreamIndex: Int, reason: AttachedPictures.LeftOutReason)]
    }

    /// Decides what happens to every attached picture in `fullPlan` (see the
    /// file header and `AttachedPictures.pictureSupport`). Without the
    /// source's streams nothing can be known to be a picture, and the plan is
    /// returned as it is.
    func pictureDecisions(for fullPlan: OutputStreamPlan) -> PictureDecisions {
        guard let sources = sourceStreamsByIndex else {
            return PictureDecisions(plan: fullPlan, attachments: [], leftOut: [])
        }
        let container = resolveContainerFormat()
        let support = AttachedPictures.pictureSupport(in: container)
        // Worked out on the FULL plan: pictures are video streams, but they
        // never decide whether the output has video (that is the profile's
        // video settings).
        let noVideo = outputHasNoVideo(plan: fullPlan)
        let pictures = fullPlan.entries.filter { $0.inputIndex == 0 && isAttachedPicture($0, sources: sources) }
        let unnamed = pictures.filter { sources[$0.sourceStreamIndex]?.attachmentFileName?.isEmpty ?? true }.count

        var attachments: [AttachedPictureAttachment] = []
        var leftOut: [(sourceStreamIndex: Int, reason: AttachedPictures.LeftOutReason)] = []
        for entry in pictures {
            let index = entry.sourceStreamIndex
            switch support {
            case .attachment:
                guard let stream = sources[index],
                      let format = AttachedPictures.imageFormat(forCodec: stream.codecName) else {
                    leftOut.append((index, .unknownPictureFormat(sources[index]?.codecName)))
                    continue
                }
                guard let file = attachedPictureFiles[index] else {
                    leftOut.append((index, .noCopyToAttach))
                    continue
                }
                attachments.append(AttachedPictureAttachment(
                    sourceStreamIndex: index,
                    file: file,
                    fileName: AttachedPictures.attachmentFileName(
                        for: stream, fileExtension: format.fileExtension, isOnlyUnnamed: unnamed <= 1
                    ),
                    mimeType: AttachedPictures.attachmentMimeType(for: stream, derived: format.mimeType),
                    description: attachmentDescription(for: stream)
                ))
            case .mappedAsCoverArt:
                let codec = sources[index]?.codecName
                if noVideo {
                    leftOut.append((index, .outputHasNoVideo))
                } else if let container, !AttachedPictures.mp4CoverArtCodecs.contains(codec?.lowercased() ?? "") {
                    // Mapped, it would make ffmpeg refuse the whole job.
                    leftOut.append((index, .notMP4CoverArtFormat(codec: codec, container: container)))
                }
            case .unchecked:
                if noVideo { leftOut.append((index, .outputHasNoVideo)) }
            case .none:
                if let container { leftOut.append((index, .fileTypeCannotHoldPictures(container))) }
            }
        }

        // Attachment streams — fonts, and pictures ffmpeg reads as plain
        // attachments (BMP, WebP …): only Matroska can hold them. Into any
        // other file type they are left out, with a note, whether or not
        // "map all streams" chose them (see the file header): mapped, they
        // made ffmpeg refuse MP4 and MOV jobs, became a `bin_data` stream in
        // MPEG-TS and vanished from WebM; not chosen, they went without a
        // word.
        if let container, AttachedPictures.holdsAttachments(in: container) == false {
            for stream in sources.values.sorted(by: { $0.streamIndex < $1.streamIndex })
            where stream.streamType == .attachment {
                leftOut.append((stream.streamIndex, .attachmentNotHeld(
                    container: container, fileName: stream.attachmentFileName, mimeType: stream.attachmentMimeType
                )))
            }
        }

        let removed = Set(attachments.map(\.sourceStreamIndex) + leftOut.map(\.sourceStreamIndex))
        let plan = OutputStreamPlan(entries: fullPlan.entries.filter { entry in
            !(entry.inputIndex == 0 && removed.contains(entry.sourceStreamIndex))
        })
        return PictureDecisions(plan: plan, attachments: attachments, leftOut: leftOut)
    }

    /// An attachment's description: the stream editor's title for the
    /// picture if the person set one (an empty one clears it), otherwise the
    /// source's own. `nil` when there is none.
    private func attachmentDescription(for stream: MediaStream) -> String? {
        let text = sourceStreamEdits[stream.streamIndex]?.title ?? stream.title
        guard let text, !Self.isBlank(text) else { return nil }
        return text
    }

    /// The attached pictures this output can only keep by attaching a copy
    /// (a Matroska output), with the file extension each copy should have.
    /// The engine copies these out of the source before building the command
    /// (`attachedPictureFiles`, `AttachedPictures.copyPictures`). A picture in
    /// a format with no known file type is not listed; it is left out.
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

    /// The video-type positions (`N` in `-c:v:N`) of the attached pictures
    /// `plan` maps as streams, or `[]` when this output copies its video
    /// (`-c:v copy`) or has none (`-vn`) — `videoArguments` is what
    /// `buildVideoArguments` wrote.
    private func mappedPicturePositions(in plan: OutputStreamPlan?, videoArguments: [String]) -> [Int] {
        guard !videoPassthrough, !videoArguments.contains("-vn"),
              let plan, let sources = sourceStreamsByIndex else { return [] }
        var positions: [Int] = []
        var position = 0
        for entry in plan.entries where entry.streamType == .video {
            if isAttachedPicture(entry, sources: sources) { positions.append(position) }
            position += 1
        }
        return positions
    }

    /// `-c:v:N copy` for every attached picture the output maps as a stream,
    /// when the video is RE-ENCODED.
    ///
    /// A picture is not video: re-encoding it with the film's encoder is at
    /// best pointless, and with its `attached_pic` flag kept it is fatal —
    /// MP4 stores cover art only as JPEG, PNG or BMP, so an H.264 "picture"
    /// makes ffmpeg refuse the whole job ("codec not currently supported in
    /// container"; checked with ffmpeg 9.0.1). Copying it keeps it exactly as
    /// the source had it. (Before the language policy's second review round
    /// the flag was cleared instead, so the cover became a one-frame H.264
    /// video track.)
    func pictureCopyArguments(plan: OutputStreamPlan?, videoArguments: [String]) -> [String] {
        mappedPicturePositions(in: plan, videoArguments: videoArguments).flatMap { ["-c:v:\($0)", "copy"] }
    }

    /// The video filter chain's arguments. Normally one `-vf <chain>` for all
    /// video. When the video is re-encoded and cover art is mapped beside it,
    /// the chain is given to each REAL video stream (`-filter:v:N`) instead:
    /// ffmpeg refuses a filter on a stream it copies ("Filtering and
    /// streamcopy cannot be used together"), and the picture is copied.
    func videoFilterArguments(_ chain: String, plan: OutputStreamPlan?, videoArguments: [String]) -> [String] {
        guard !chain.isEmpty else { return [] }
        let pictures = Set(mappedPicturePositions(in: plan, videoArguments: videoArguments))
        guard !pictures.isEmpty, let plan else { return ["-vf", chain] }
        let videoCount = plan.entries.filter { $0.streamType == .video }.count
        return (0..<videoCount).filter { !pictures.contains($0) }.flatMap { ["-filter:v:\($0)", chain] }
    }

    /// `-attach` arguments for `attachments`, each with the `mimetype` and
    /// `filename` metadata Matroska attachments need (ffmpeg refuses an
    /// attachment with no MIME type) and, when the picture has one, its
    /// description as `title` (ffmpeg writes an attachment's `title` as
    /// Matroska's `FileDescription` — checked with ffmpeg 9.0.1; the second
    /// review found it was dropped). Streams made by `-attach` come after
    /// every mapped stream, so the first one's attachment-counted position is
    /// the number of attachments `plan` maps (fonts, for example).
    func attachArguments(_ attachments: [AttachedPictureAttachment], after plan: OutputStreamPlan) -> [String] {
        let mappedAttachments = plan.entries.filter { $0.streamType == .attachment }.count
        var args: [String] = []
        for (offset, attachment) in attachments.enumerated() {
            let specifier = "-metadata:s:t:\(mappedAttachments + offset)"
            args += ["-attach", attachment.file.path]
            args += [specifier, "mimetype=\(attachment.mimeType)", specifier, "filename=\(attachment.fileName)"]
            if let description = attachment.description {
                args += [specifier, "title=\(description)"]
            }
        }
        return args
    }
}
// MARK: - The copying step

extension AttachedPictures {

    /// Copies each picture in `needed` out of `input` into `folder`, byte
    /// for byte (`extractionArguments`), running ffmpeg through `run` — the
    /// step every path that writes a Matroska output takes before it builds
    /// its command, so the cover art is attached rather than left out: the
    /// full encode (`EncodingEngine.encode`), a pipeline's encode step
    /// (`EncodingPipelineExecutor`), the Shortcuts action and the quality
    /// preview. One function, so they cannot drift apart.
    ///
    /// Returns the copies that were made, keyed by the picture's stream
    /// number. A picture whose copy failed, or came out empty, is simply not
    /// in the result: the argument builder then leaves it out and the job's
    /// notes say so. Never throws — a missing cover is reported, not fatal.
    ///
    /// - Parameters:
    ///   - needed: What `attachedPicturesNeedingCopies()` listed.
    ///   - input: The source file.
    ///   - folder: An existing folder of the caller's; the caller removes it
    ///     (and so the copies) when the job ends.
    ///   - run: Runs ffmpeg with the given arguments; throws on failure.
    public static func copyPictures(
        _ needed: [(streamIndex: Int, fileExtension: String)],
        from input: URL,
        into folder: URL,
        run: (_ arguments: [String]) async throws -> Void
    ) async -> [Int: URL] {
        var copies: [Int: URL] = [:]
        for picture in needed {
            let copy = folder.appendingPathComponent("attached-picture-\(picture.streamIndex).\(picture.fileExtension)")
            do {
                try await run(extractionArguments(input: input, streamIndex: picture.streamIndex, output: copy))
                let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 { copies[picture.streamIndex] = copy }
            } catch {
                // Not fatal: the picture is left out, and the notes say so.
            }
        }
        return copies
    }
}
