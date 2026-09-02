// ============================================================================
// MeedyaConverter — CLI Disc Command
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import Foundation
import ConverterEngine

// MARK: - Output format

/// Text or JSON output selector shared by the `disc` subcommands. Named
/// distinctly from each command's own nested selectors to avoid collisions.
enum DiscOutputFormat: String, ExpressibleByArgument, CaseIterable {
    case text
    case json
}

// MARK: - disc (parent)

/// `meedya-convert disc` — read and image optical discs by shelling out to
/// `cdrdao` (located via `BundledToolLocator`, never linked — decision
/// DR-0001). All testable logic lives in `ConverterEngine`; this command tree
/// is thin argument plumbing over it, following `ProbeCommand`'s conventions
/// (`AsyncParsableCommand`, `ExitCode`, `printStderr`).
struct DiscCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disc",
        abstract: "Read and image optical discs.",
        subcommands: [
            DiscDrivesCommand.self,
            DiscTocCommand.self,
            DiscImageCommand.self,
        ]
    )
}

// MARK: - disc drives

/// `meedya-convert disc drives` — discover optical drives via `cdrdao
/// scanbus` and print the parsed rows.
struct DiscDrivesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drives",
        abstract: "List optical drives cdrdao can see."
    )

    @Option(name: .customLong("format"), help: "Output format: text (default), json.")
    var outputFormat: DiscOutputFormat = .text

    @Option(name: .customLong("cdrdao"), help: "Full path to the cdrdao binary (overrides discovery).")
    var cdrdaoPath: String?

    func run() async throws {
        let locator = BundledToolLocator(toolName: "cdrdao", userOverridePath: cdrdaoPath)
        let cdrdao: String
        do {
            cdrdao = try locator.locate()
        } catch {
            printStderr("cdrdao not found: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.inputNotFound.rawValue)
        }

        let arguments = RawCDReadPlanner.buildScanbusArguments()
        let result = DiscProcessRunner.run(executable: cdrdao, arguments: arguments)
        guard result.launched else {
            printStderr("Failed to launch cdrdao: \(result.output)")
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }

        // cdrdao prints scanbus results on stderr; parse whatever it printed.
        let drives = DriveListingParser.parseScanbus(result.output)

        switch outputFormat {
        case .text:
            if drives.isEmpty {
                print("No optical drives detected.")
            } else {
                for drive in drives {
                    print("\(drive.device ?? "(no device node)")  \(drive.description)")
                }
            }
        case .json:
            printJSON(drives)
        }
    }
}

// MARK: - disc toc

/// `meedya-convert disc toc` — read a disc's table of contents and print it.
struct DiscTocCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "toc",
        abstract: "Read and print a disc's table of contents."
    )

    @Option(name: .customLong("device"), help: "cdrdao --device string (e.g. /dev/sr0).")
    var device: String

    @Option(name: .customLong("driver"), help: "cdrdao --driver value (e.g. generic-mmc).")
    var driver: String?

    @Option(name: [.customShort("o"), .customLong("output")], help: "Where to write the .toc (default: a temp file, deleted after parse).")
    var tocPath: String?

    @Flag(name: .customLong("fast"), help: "Use --fast-toc (skips the deep ISRC/pregap scan).")
    var fastToc = false

    @Option(name: [.short, .customLong("format")], help: "Output format: text (default), json.")
    var outputFormat: DiscOutputFormat = .text

    @Option(name: .customLong("cdrdao"), help: "Full path to the cdrdao binary (overrides discovery).")
    var cdrdaoPath: String?

    func run() async throws {
        let locator = BundledToolLocator(toolName: "cdrdao", userOverridePath: cdrdaoPath)
        let cdrdao: String
        do {
            cdrdao = try locator.locate()
        } catch {
            printStderr("cdrdao not found: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.inputNotFound.rawValue)
        }

        let usingTemp = tocPath == nil
        let resolvedTocPath = tocPath ?? NSTemporaryDirectory() + "meedya-disc-\(UUID().uuidString).toc"
        defer {
            if usingTemp { try? FileManager.default.removeItem(atPath: resolvedTocPath) }
        }

        let controller = DiscImagingController(cdrdaoPath: cdrdao)
        let toc: DiscTableOfContents
        do {
            toc = try await controller.readTableOfContents(
                device: device,
                driver: driver,
                fastToc: fastToc,
                tocPath: resolvedTocPath
            )
        } catch {
            printStderr("Reading the TOC failed: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }

        switch outputFormat {
        case .text:
            printTOC(toc)
        case .json:
            printJSON(toc)
        }
    }

    private func printTOC(_ toc: DiscTableOfContents) {
        print("Disc type: \(toc.discType)")
        if let catalog = toc.catalogNumber { print("Catalogue: \(catalog)") }
        if let title = toc.cdText?.albumTitle { print("Album: \(title)") }
        if let artist = toc.cdText?.albumArtist { print("Artist: \(artist)") }
        print("Tracks: \(toc.tracks.count)")
        print("Lead-out sector: \(toc.leadOutSector)")
        for track in toc.tracks {
            var line = "  \(String(format: "%02d", track.number)) \(track.trackMode.rawValue)"
            line += " start=\(track.startSector) length=\(track.sectorCount)"
            if track.hasPreEmphasis { line += " [pre-emphasis]" }
            if let isrc = track.isrc { line += " ISRC=\(isrc)" }
            print(line)
        }
    }
}

// MARK: - disc image

/// `meedya-convert disc image` — the full read pipeline: DRM gate, `cdrdao
/// read-cd`, then finalisation into a verified BIN/CUE pair.
struct DiscImageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "image",
        abstract: "Image a physical Audio CD into a verified BIN/CUE pair."
    )

    @Option(name: .customLong("device"), help: "cdrdao --device string (e.g. /dev/sr0).")
    var device: String

    @Option(name: [.customShort("o"), .customLong("output")], help: "Base output path; .bin/.cue are derived from it.")
    var outputPath: String

    @Option(name: .customLong("image-format"), help: "Image format (only 'bin' is supported).")
    var imageFormat: String = "bin"

    @Option(name: .customLong("driver"), help: "cdrdao --driver value (e.g. generic-mmc).")
    var driver: String?

    @Option(name: .customLong("speed"), help: "Read speed (default: drive default). Effect on cdrdao read-cd is drive/build-dependent — confirmed on the hardware matrix.")
    var readSpeed: Int?

    @Option(name: .customLong("paranoia"), help: "Error-correction level 0–3 (default 3 = full).")
    var paranoia: Int = 3

    @Flag(name: .customLong("subchannel"), help: "Capture raw+subchannel (2448-byte) sectors.")
    var captureSubchannel = false

    @Flag(name: .customLong("skip-verify"), help: "Skip the post-read byte-count/SHA-256 verification.")
    var skipVerify = false

    @Flag(name: .customLong("overwrite"), help: "Delete an existing .bin/.toc before reading.")
    var overwrite = false

    @Option(name: .customLong("cdrdao"), help: "Full path to the cdrdao binary (overrides discovery).")
    var cdrdaoPath: String?

    /// `CDParanoiaMode.rawValue` only covers 0–3; reject anything outside
    /// that range up front (matching `ServeCommand.validate()`'s style)
    /// rather than silently clamping a typo like `--paranoia 30` down to 3.
    func validate() throws {
        guard CDParanoiaMode(rawValue: paranoia) != nil else {
            throw ValidationError("--paranoia must be between 0 and 3 (0 = disabled, 3 = full).")
        }
    }

    func run() async throws {
        // Locate cdrdao.
        let locator = BundledToolLocator(toolName: "cdrdao", userOverridePath: cdrdaoPath)
        let cdrdao: String
        do {
            cdrdao = try locator.locate()
        } catch {
            printStderr("cdrdao not found: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.inputNotFound.rawValue)
        }

        // Parse the requested image format; the wiring makes anything but .bin
        // fail loudly rather than silently mislabel a BIN/CUE.
        guard let format = DiscImageFormat(rawValue: imageFormat.lowercased()) else {
            printStderr("Unknown image format: \(imageFormat)")
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        // `validate()` already proved this is in range.
        let paranoiaMode = CDParanoiaMode(rawValue: paranoia) ?? .full

        // Build the (previously dead) ImagingConfig and bridge it — this is
        // where a non-.bin format throws ImagingError.unsupportedImageFormat.
        let imagingConfig = ImagingConfig(
            sourcePath: device,
            outputPath: outputPath,
            imageFormat: format,
            readSpeed: readSpeed,
            verifyAfterCopy: !skipVerify
        )
        let config: RawCDImagingConfig
        do {
            config = try RawCDImagingConfig(
                imagingConfig: imagingConfig,
                device: device,
                driver: driver,
                paranoia: paranoiaMode,
                captureSubchannel: captureSubchannel
            )
        } catch {
            printStderr(error.localizedDescription)
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        // Honour --overwrite (cdrdao refuses an existing toc-file).
        if overwrite {
            try? FileManager.default.removeItem(atPath: config.tocPath)
            try? FileManager.default.removeItem(atPath: config.binPath)
        }

        let controller = DiscImagingController(cdrdaoPath: cdrdao)

        // Read the TOC first (a fast pass — the drive's table of contents, not
        // the audio data). This is what makes the guards below operate on the
        // real disc instead of an assumption:
        //
        //   1. CAPABILITY GUARD (P1). This path faithfully images Red Book
        //      (CD-DA) audio only. A disc carrying a data session is a
        //      mixed-mode / enhanced-CD / data disc, which a plain audio
        //      BIN/CUE cannot represent faithfully — that is a later phase
        //      (#108 / #135 / #492), not a silent partial image. Refuse it
        //      with a clear reason rather than writing a lossy artefact. This
        //      guard is genuinely reachable: any data-bearing disc trips it.
        //
        //   2. PROTECTION GATE. Having proven above that the disc is audio-only,
        //      `discType: .audioCd` is now a checked fact, not a guess, and the
        //      detector correctly classifies CD-DA as unprotected. The gate's
        //      *refusal* cases (CSS / AACS / BD+ / AACS 2.0) are driven by
        //      markers a DVD/BD/UHD reader supplies from a filesystem / IFO
        //      scan; those readers are later phases, so on this CD path the
        //      gate proceeds — which is correct, not missing detection.
        let tocProbePath = NSTemporaryDirectory()
            + "meedya-disc-probe-\(UUID().uuidString).toc"
        let probedTOC: DiscTableOfContents
        do {
            probedTOC = try await controller.readTableOfContents(
                device: device,
                driver: driver,
                session: nil,
                tocPath: tocProbePath
            )
        } catch {
            printStderr("Could not read the disc's table of contents: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }
        try? FileManager.default.removeItem(atPath: tocProbePath)
        try? FileManager.default.removeItem(
            atPath: (tocProbePath as NSString).deletingPathExtension + ".bin"
        )

        if probedTOC.tracks.contains(where: { $0.isData }) {
            printStderr(
                "This disc contains a data session. The Audio CD image path "
                + "faithfully images Red Book (CD-DA) audio only; full "
                + "mixed-mode / multisession disc imaging is a later phase "
                + "(see issues #108 / #135 / #492)."
            )
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        let markers = DiscProtectionMarkers(discType: .audioCd)

        let stream: AsyncStream<ImagingProgress>
        do {
            stream = try controller.startImaging(config: config, markers: markers)
        } catch let error as DiscImagingError {
            if case .protectedDisc = error {
                printStderr(error.localizedDescription)
                throw ExitCode(ExitCodes.validationFailed.rawValue)
            }
            printStderr(error.localizedDescription)
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }

        for await progress in stream {
            if let fraction = progress.fractionComplete {
                printStderr(String(format: "  reading… %.1f%% (%@)", fraction * 100, progress.formattedSpeed))
            } else {
                printStderr("  reading… \(progress.bytesCopied) bytes")
            }
        }

        if let code = controller.exitCode, code != 0 {
            printStderr("cdrdao exited with code \(code): \(controller.errorOutput.prefix(500))")
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }

        // Finalise: subchannel split, .cue emission, verification.
        do {
            let result = try await controller.finalizeImage(config: config)
            print("Wrote \(config.binPath)")
            print("Wrote \(result.cuePath)")
            print("Tracks: \(result.toc.tracks.count), lead-out sector: \(result.toc.leadOutSector)")
            let verification = result.verification
            print("Size: \(verification.byteCount) bytes (expected \(verification.expectedByteCount)) — "
                + (verification.sizeMatches ? "match" : "MISMATCH"))
            if let sha = verification.sha256Hex {
                print("SHA-256: \(sha)")
            }
        } catch {
            printStderr("Finalisation failed: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }
    }
}

// MARK: - Shared helpers

/// Emit a `Codable` value as pretty JSON on stdout.
private func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

/// A tiny synchronous process runner for one-shot discovery commands
/// (`cdrdao scanbus`). Captures stdout and stderr together, because cdrdao
/// prints scanbus results on stderr. This launches a real subprocess and is
/// hardware-verified on the manual matrix; where cdrdao is absent the caller
/// surfaces the failure honestly.
enum DiscProcessRunner {
    struct Result {
        let launched: Bool
        let exitCode: Int32
        let output: String
    }

    static func run(executable: String, arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(launched: false, exitCode: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return Result(launched: true, exitCode: process.terminationStatus, output: output)
    }
}
