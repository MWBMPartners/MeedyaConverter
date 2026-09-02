// ============================================================================
// MeedyaConverter — RawCDReadPlanner
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - RawCDImagingConfig

/// Sendable configuration for a single `cdrdao read-cd` run that images a
/// physical Audio CD into a raw BIN/CUE pair (issue #495, P1).
///
/// Per decision DR-0001 the raw read path *shells out* to the `cdrdao`
/// command-line tool — the tool is located, never linked — so this type is a
/// pure value description of one invocation, with no device or process
/// coupling. It also carries the bridge that finally *consumes*
/// `ImagingConfig.imageFormat`, which was dead configuration until this batch:
/// `init(imagingConfig:device:...)` refuses every image format except `.bin`,
/// so the previously ignored field now has observable behaviour.
public struct RawCDImagingConfig: Codable, Sendable, Equatable {

    /// The device string handed straight to `cdrdao --device`. On Linux this is
    /// a node such as `/dev/sr0`; on macOS it is whatever `cdrdao scanbus`
    /// reported for the drive — we never fabricate a node, because the exact
    /// spelling cdrdao accepts is drive- and platform-specific and only the
    /// hardware matrix settles it (see #495).
    public var device: String

    /// The `cdrdao --driver` value (e.g. `generic-mmc`); `nil` lets cdrdao
    /// autodetect. Some drives need an explicit driver — that is a
    /// hardware-matrix finding, not something we can guess here.
    public var driver: String?

    /// The `--speed` multiplier; `nil` uses the drive default. A slower read
    /// often recovers more from scratched media.
    public var readSpeed: Int?

    /// Error-correction aggressiveness. `CDParanoiaMode.rawValue` (0–3) is
    /// passed verbatim as cdrdao's `--paranoia-mode` argument — the two scales
    /// coincide, so the mapping is 1:1 with no translation table.
    public var paranoia: CDParanoiaMode

    /// When `true`, `--read-subchan rw_raw` is added, so cdrdao writes
    /// 2448-byte sectors (2352 main + 96 subchannel). The subchannel is split
    /// out afterwards by `SubchannelCodec`, which models exactly this layout.
    public var captureSubchannel: Bool

    /// The session to read for a multi-session disc; `nil` reads session 1.
    public var session: Int?

    /// Absolute path of the `.bin` datafile cdrdao writes (`--datafile`).
    public var binPath: String

    /// Absolute path of the `.toc` file cdrdao writes (its final positional
    /// argument). cdrdao refuses to overwrite an existing toc-file, so callers
    /// must clear it first — the executor surfaces the refusal as
    /// `DiscImagingError.outputExists`.
    public var tocPath: String

    /// Whether to run byte-count + SHA-256 verification once cdrdao exits 0.
    public var verifyAfterRead: Bool

    public init(
        device: String,
        driver: String? = nil,
        readSpeed: Int? = nil,
        paranoia: CDParanoiaMode = .full,
        captureSubchannel: Bool = false,
        session: Int? = nil,
        binPath: String,
        tocPath: String,
        verifyAfterRead: Bool = true
    ) {
        self.device = device
        self.driver = driver
        self.readSpeed = readSpeed
        self.paranoia = paranoia
        self.captureSubchannel = captureSubchannel
        self.session = session
        self.binPath = binPath
        self.tocPath = tocPath
        self.verifyAfterRead = verifyAfterRead
    }

    /// Bridge from the existing (previously dead) `ImagingConfig`.
    ///
    /// This is the single place `ImagingConfig.imageFormat` is finally read:
    /// only `.bin` (BIN/CUE) is a valid target for the raw Audio CD executor,
    /// so any other format — including the newly declared `.ccd` — throws
    /// `ImagingError.unsupportedImageFormat`, wired through
    /// `DiscImageFormat.supportsRawAudioImaging`. This makes the format field
    /// observable behaviour rather than ignored configuration, and refuses
    /// honestly instead of silently emitting a `.bin` under the wrong name.
    ///
    /// The `.bin`/`.toc` output paths are derived from
    /// `imagingConfig.outputPath` by replacing its extension; `readSpeed` and
    /// `verifyAfterRead` are carried across from the source config.
    ///
    /// - Parameters:
    ///   - imagingConfig: The generic imaging configuration whose
    ///     `imageFormat` gates this conversion.
    ///   - device: The cdrdao `--device` string (see `device`).
    ///   - driver: Optional cdrdao `--driver` override.
    ///   - paranoia: Error-correction aggressiveness.
    ///   - captureSubchannel: Whether to capture 2448-byte raw+sub sectors.
    /// - Throws: `ImagingError.unsupportedImageFormat` when
    ///   `imagingConfig.imageFormat` is anything other than `.bin`.
    public init(
        imagingConfig: ImagingConfig,
        device: String,
        driver: String? = nil,
        paranoia: CDParanoiaMode = .full,
        captureSubchannel: Bool = false
    ) throws {
        guard imagingConfig.imageFormat.supportsRawAudioImaging else {
            throw ImagingError.unsupportedImageFormat(imagingConfig.imageFormat)
        }

        let base = URL(fileURLWithPath: imagingConfig.outputPath).deletingPathExtension()
        self.init(
            device: device,
            driver: driver,
            readSpeed: imagingConfig.readSpeed,
            paranoia: paranoia,
            captureSubchannel: captureSubchannel,
            session: nil,
            binPath: base.appendingPathExtension("bin").path,
            tocPath: base.appendingPathExtension("toc").path,
            verifyAfterRead: imagingConfig.verifyAfterCopy
        )
    }
}

// MARK: - RawCDReadPlanner

/// Pure builders for the `cdrdao` command lines the Audio CD executor runs,
/// plus the sector arithmetic used to size and verify the resulting image.
///
/// This mirrors the static-builder house style of `DiscImager` and
/// `AudioCDReader`: every method is a pure function from a value to an
/// argument array, with no process launch and no I/O, so the exact wire form
/// of each invocation is unit-testable in CI. The process launch itself lives
/// in `DiscImagingController`, which is hardware-verified on the manual matrix.
///
/// `cdrdao`'s CLI shape is `cdrdao <command> [options] <toc-file>`: the
/// sub-command comes first, options follow, and the toc-file is always the
/// final positional argument. These builders honour that ordering exactly.
public struct RawCDReadPlanner: Sendable {

    /// Bytes per main-channel sector — Red Book / Yellow Book raw sector size.
    private static let mainSectorBytes: Int64 = 2352

    /// Bytes per sector when subchannel data is captured alongside the main
    /// channel (2352 + 96).
    private static let rawWithSubBytes: Int64 = 2448

    /// Build the `cdrdao read-toc` argument vector (phase 1 — TOC scan, no
    /// audio data is read into the datafile).
    ///
    /// Without `--fast-toc`, cdrdao scans the whole disc for ISRC codes, the
    /// media catalogue number, pre-gaps and sub-indexes; P1 defaults to the
    /// full scan because that fidelity is the entire point of the feature.
    ///
    /// - Parameters:
    ///   - device: cdrdao `--device` string.
    ///   - driver: Optional `--driver` value.
    ///   - session: Optional session number for multi-session discs.
    ///   - fastToc: When `true`, adds `--fast-toc` to skip the deep scan.
    ///   - datafileName: The name emitted into the `.toc`'s `FILE` statements
    ///     via `--datafile` (the eventual `.bin`).
    ///   - tocPath: Output `.toc` path — the final positional argument.
    /// - Returns: The full argument array (excluding the `cdrdao` binary).
    public static func buildReadTocArguments(
        device: String,
        driver: String? = nil,
        session: Int? = nil,
        fastToc: Bool = false,
        datafileName: String,
        tocPath: String
    ) -> [String] {
        var args = ["read-toc", "--device", device]
        if let driver { args += ["--driver", driver] }
        if let session { args += ["--session", "\(session)"] }
        if fastToc { args.append("--fast-toc") }
        args += ["--datafile", datafileName, "-v", "2", tocPath]
        return args
    }

    /// Build the `cdrdao read-cd --read-raw` argument vector (phase 2 — the
    /// actual image read).
    ///
    /// `--read-raw` keeps data tracks in raw 2352-byte form (audio tracks are
    /// always 2352), so mixed-mode discs stay faithful. `--paranoia-mode` is
    /// the config's `CDParanoiaMode.rawValue` verbatim. `--read-subchan
    /// rw_raw` (added only when `captureSubchannel` is set) appends 96
    /// subchannel bytes per sector, giving 2448-byte sectors in the datafile.
    ///
    /// - Parameter config: The read configuration.
    /// - Returns: The full argument array (excluding the `cdrdao` binary),
    ///   with `config.tocPath` as the final positional argument.
    /// Note on `--speed`: cdrdao applies a speed to writing reliably, but its
    /// effect on the `read-cd` path is drive- and build-dependent (some builds
    /// ignore it, some reject it). It is emitted only when `config.readSpeed`
    /// is set, and is confirmed on the manual hardware matrix.
    public static func buildReadCdArguments(config: RawCDImagingConfig) -> [String] {
        var args = ["read-cd", "--read-raw", "--device", config.device]
        if let driver = config.driver { args += ["--driver", driver] }
        if let speed = config.readSpeed { args += ["--speed", "\(speed)"] }
        args += ["--paranoia-mode", "\(config.paranoia.rawValue)"]
        if config.captureSubchannel { args += ["--read-subchan", "rw_raw"] }
        if let session = config.session { args += ["--session", "\(session)"] }
        args += ["--datafile", config.binPath, "-v", "2", config.tocPath]
        return args
    }

    /// Build the `cdrdao scanbus` argument vector for drive discovery. Its
    /// output is parsed by `DriveListingParser.parseScanbus`.
    public static func buildScanbusArguments() -> [String] {
        ["scanbus"]
    }

    /// Build the macOS pre-step that unmounts a medium so cdrdao can claim the
    /// device — cdrdao cannot open a mounted disc. Pure builder only; the
    /// launch is hardware-verified on the matrix.
    ///
    /// - Parameter diskNode: The `/dev/diskN` node to unmount.
    /// - Returns: The tool name and its argument array.
    /// On macOS the medium must be unmounted before cdrdao can claim the raw
    /// device, so this builds the `diskutil unmountDisk` command.
    ///
    /// It is a pure builder and is **not yet wired to an executor.** Two things
    /// block that, and both need an optical drive to get right, so they are
    /// deferred to the hardware matrix rather than guessed at here: the actual
    /// unmount is device I/O that CI cannot exercise, and — more subtly — the
    /// caller must map cdrdao's `--device` string to the matching `diskutil`
    /// disk node (`/dev/diskN`), a mapping that is drive- and version-dependent
    /// and cannot be verified without hardware. The builder is provided so that
    /// wiring is a one-line call once that mapping is settled on the matrix.
    public static func buildMacOSUnmountArguments(diskNode: String) -> (tool: String, arguments: [String]) {
        ("diskutil", ["unmountDisk", diskNode])
    }

    /// The exact byte count a faithful `.bin` (or raw+subchannel capture) must
    /// have for a disc whose lead-out is `toc.leadOutSector`: the total sector
    /// count times the per-sector size (2352, or 2448 when the subchannel is
    /// captured). Used both to size the progress bar and to verify the image
    /// after the read.
    ///
    /// - Parameters:
    ///   - toc: The disc table of contents (its `leadOutSector` is the total
    ///     sector count).
    ///   - includeSubchannel: Whether the capture carries 96 subchannel bytes
    ///     per sector.
    /// - Returns: The expected datafile size in bytes.
    public static func expectedBinByteCount(toc: DiscTableOfContents, includeSubchannel: Bool) -> Int64 {
        Int64(toc.leadOutSector) * (includeSubchannel ? rawWithSubBytes : mainSectorBytes)
    }
}
