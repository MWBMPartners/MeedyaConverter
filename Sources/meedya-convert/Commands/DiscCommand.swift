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
            DiscIdentifyCommand.self,
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

        let usingTemp = tocPath == nil
        let resolvedTocPath = tocPath ?? NSTemporaryDirectory() + "meedya-disc-\(UUID().uuidString).toc"
        defer {
            // Both files: cdrdao writes a .bin datafile beside the .toc.
            if usingTemp {
                try? FileManager.default.removeItem(atPath: resolvedTocPath)
                try? FileManager.default.removeItem(
                    atPath: (resolvedTocPath as NSString).deletingPathExtension + ".bin"
                )
            }
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

// MARK: - disc identify

/// What to send to MeedyaDB. A CLI-local mirror of the engine's
/// `MeedyaDBSubmissionMode` rather than a retroactive `ExpressibleByArgument`
/// conformance on an imported type, which Swift 6 warns about.
enum DiscSubmissionModeArgument: String, ExpressibleByArgument, CaseIterable {
    case anonymous
    case full

    var engineMode: MeedyaDBSubmissionMode {
        switch self {
        case .anonymous: return .anonymous
        case .full: return .full
        }
    }
}

/// `meedya-convert disc identify` — work out what a music disc actually is.
///
/// Computes the disc's own IDs from its table of contents (offline and
/// deterministic), asks MusicBrainz which release it is, and — only when
/// explicitly asked with `--submit` — contributes the result to MeedyaDB.
///
/// Sending anything to MeedyaDB is opt-in on every single run: contributing
/// is an outward-facing act, so it never happens because of a stored setting
/// the user has forgotten about. The API key is read from the environment
/// (`MEEDYADB_API_KEY`), never taken as an argument, because arguments are
/// visible to every other user on the machine through `ps`.
struct DiscIdentifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "identify",
        abstract: "Identify a music disc, and optionally contribute it to MeedyaDB."
    )

    /// The environment variable the MeedyaDB API key is read from.
    static let apiKeyEnvironmentVariable = "MEEDYADB_API_KEY"

    @Option(name: .customLong("device"), help: "cdrdao --device string to read the disc from (e.g. /dev/sr0).")
    var device: String?

    @Option(name: .customLong("toc"), help: "Identify a .toc file read earlier, instead of a disc in a drive.")
    var tocFile: String?

    @Option(name: .customLong("driver"), help: "cdrdao --driver value (e.g. generic-mmc). Only used with --device.")
    var driver: String?

    @Flag(name: .customLong("fast"), help: "Use --fast-toc when reading the disc (skips the deep ISRC/pregap scan).")
    var fastToc = false

    @Flag(name: .customLong("offline"), help: "Work out the disc IDs only. Contacts nothing, sends nothing.")
    var offline = false

    @Flag(name: .customLong("submit"), help: "Contribute the result to MeedyaDB. Never happens unless you ask.")
    var submit = false

    // The environment variable is named literally here: a property
    // initializer cannot reach the static above it.
    @Option(name: .customLong("meedyadb-url"), help: "MeedyaDB base URL. The API key comes from MEEDYADB_API_KEY.")
    var meedyaDBURL: String?

    @Option(name: .customLong("label"), help: "What is printed on the disc. Only ever sent with --submission full.")
    var label: String?

    @Option(name: .customLong("submission"), help: "What to send: anonymous (default) or full.")
    var submissionMode: DiscSubmissionModeArgument = .anonymous

    @Option(name: .customLong("format"), help: "Output format: text (default), json.")
    var outputFormat: DiscOutputFormat = .text

    @Option(name: .customLong("cdrdao"), help: "Full path to the cdrdao binary (overrides discovery).")
    var cdrdaoPath: String?

    // MARK: Validate

    /// Rejects flag combinations that would quietly do less than the user
    /// asked for. `--offline --submit` is the one that matters: it parses
    /// fine, exits 0, and sends nothing, while also skipping the loud
    /// "MeedyaDB isn't set up" check — a silent no-op in response to an
    /// explicit instruction, which is exactly what this command must never do.
    func validate() throws {
        if offline && submit {
            throw ValidationError(
                "--offline and --submit can't be used together: --offline contacts nothing and sends nothing."
            )
        }
        if offline && meedyaDBURL != nil {
            throw ValidationError("--meedyadb-url has no effect with --offline, which sends nothing.")
        }
        if !submit && submissionMode == .full {
            throw ValidationError("--submission full only means something with --submit.")
        }
    }

    // MARK: Run

    func run() async throws {
        let toc = try await loadTableOfContents()

        // --offline stops here, before anything leaves the machine.
        if offline {
            let identity = MusicDiscIdentifier.identity(for: toc)
            let result = MusicDiscIdentificationResult(
                identity: identity,
                contribution: .notAttempted(reason: "--offline was used, so nothing was sent.")
            )
            emit(result)
            return
        }

        let identifier = try makeIdentifier()
        let result: MusicDiscIdentificationResult
        do {
            result = try await identifier.identify(
                toc: toc,
                labelText: label,
                contribute: submit,
                mode: submissionMode.engineMode
            )
        } catch is CancellationError {
            printStderr("Cancelled.")
            throw ExitCode(ExitCodes.interrupted.rawValue)
        }

        emit(result)

        // Identifying nothing is NOT a failure: a disc MusicBrainz has never
        // seen is a perfectly good answer, and the disc IDs are still useful.
        // But `--submit` is an explicit instruction, so ANY outcome where
        // nothing reached MeedyaDB exits non-zero — a script must never read
        // "exit 0" as "contributed" when nothing was.
        switch result.contribution {
        case .succeeded:
            break
        case .failed(let reason):
            printStderr("Contributing to MeedyaDB failed: \(reason)")
            throw ExitCode(ExitCodes.generalError.rawValue)
        case .notAttempted(let reason):
            if submit {
                printStderr("--submit was asked for, but nothing was sent: \(reason)")
                throw ExitCode(ExitCodes.generalError.rawValue)
            }
        }
    }

    // MARK: Loading the TOC

    private func loadTableOfContents() async throws -> DiscTableOfContents {
        switch (device, tocFile) {
        case (nil, nil), (.some, .some):
            printStderr("Choose exactly one source: --device <drive> to read a disc, or --toc <file> to read a saved .toc.")
            throw ExitCode(ExitCodes.invalidArguments.rawValue)

        case (nil, .some(let path)):
            let text: String
            do {
                text = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                printStderr("Could not read \(path): \(error.localizedDescription)")
                throw ExitCode(ExitCodes.inputNotFound.rawValue)
            }
            do {
                return try CdrdaoTocParser.parse(text)
            } catch {
                printStderr("\(path) is not a .toc this tool understands: \(error.localizedDescription)")
                throw ExitCode(ExitCodes.validationFailed.rawValue)
            }

        case (.some(let devicePath), nil):
            let locator = BundledToolLocator(toolName: "cdrdao", userOverridePath: cdrdaoPath)
            let cdrdao: String
            do {
                cdrdao = try locator.locate()
            } catch {
                printStderr("cdrdao not found: \(error.localizedDescription)")
                throw ExitCode(ExitCodes.inputNotFound.rawValue)
            }

            let scratchPath = NSTemporaryDirectory() + "meedya-identify-\(UUID().uuidString).toc"
            defer {
                // cdrdao writes a .bin datafile beside the .toc even for a
                // read-toc, so clear both or every run leaks a sidecar.
                try? FileManager.default.removeItem(atPath: scratchPath)
                try? FileManager.default.removeItem(
                    atPath: (scratchPath as NSString).deletingPathExtension + ".bin"
                )
            }

            let controller = DiscImagingController(cdrdaoPath: cdrdao)
            do {
                return try await controller.readTableOfContents(
                    device: devicePath,
                    driver: driver,
                    fastToc: fastToc,
                    tocPath: scratchPath
                )
            } catch {
                printStderr("Reading the disc failed: \(error.localizedDescription)")
                throw ExitCode(ExitCodes.encodingFailed.rawValue)
            }
        }
    }

    // MARK: Building the identifier

    /// Fails loudly when `--submit` was asked for but MeedyaDB isn't set up.
    /// Silently skipping would be worse: the user asked to contribute and
    /// would be told nothing was wrong while nothing was sent.
    private func makeIdentifier() throws -> MusicDiscIdentifier {
        guard submit else { return MusicDiscIdentifier() }

        // Trim exactly as `MeedyaDBPublisherConfig.isUsable` does. With the
        // narrower `.whitespaces` an API key that is only a newline — easy to
        // produce with MEEDYADB_API_KEY=$(some-command) — would pass this
        // gate, then be rejected downstream as "not configured", which the
        // engine correctly treats as "nothing sent". The run would exit 0
        // having sent nothing, despite an explicit --submit.
        let apiKey = ProcessInfo.processInfo.environment[Self.apiKeyEnvironmentVariable] ?? ""
        let baseURL = meedyaDBURL ?? ""
        var missing: [String] = []
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("--meedyadb-url") }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append(Self.apiKeyEnvironmentVariable) }
        guard missing.isEmpty else {
            printStderr("--submit needs MeedyaDB set up first. Missing: \(missing.joined(separator: " and ")).")
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        return MusicDiscIdentifier(
            meedyaDB: MeedyaDBPublisherConfig(baseURL: baseURL, apiKey: apiKey, enabled: true)
        )
    }

    // MARK: Output

    private func emit(_ result: MusicDiscIdentificationResult) {
        switch outputFormat {
        case .text:
            printIdentification(result)
        case .json:
            printJSON(DiscIdentifyReport(result))
        }
    }

    private func printIdentification(_ result: MusicDiscIdentificationResult) {
        let identity = result.identity
        print("Disc ID (music portion): \(identity.musicDiscID ?? "—")")
        if identity.isEnhancedCD, let whole = identity.wholeDiscID {
            print("Disc ID (whole disc):    \(whole)")
            print("  This is an Enhanced CD: it carries a data session as well as the music.")
            print("  MusicBrainz is asked about the music portion; MeedyaDB records both.")
        }
        if let source = identity.leadOutSource {
            print("Music session end from:  \(Self.describe(source))")
        }
        if let fingerprint = identity.tocFingerprint {
            print("TOC fingerprint:         \(fingerprint)")
        }
        print("Audio tracks:            \(identity.audioTrackCount)")
        print("")
        print(result.summary)

        for match in result.matches {
            var line = "  \(match.title)"
            if let artist = match.artist { line += " — \(artist)" }
            var details: [String] = []
            if let year = match.year { details.append(String(year)) }
            if let country = match.country { details.append(country) }
            if let tracks = match.trackCount { details.append("\(tracks) tracks") }
            if !details.isEmpty { line += " (\(details.joined(separator: ", ")))" }
            print(line)
            print("    MusicBrainz release: \(match.id)")
        }

        print("")
        switch result.contribution {
        case .succeeded(let ingest):
            print("MeedyaDB: sent. Disc \(ingest.discPublicId)"
                + (ingest.matched ? ", matched to a known release." : ", recorded as a new disc."))
            if let release = ingest.releasePublicId {
                print("          Release \(release)")
            }
        case .notAttempted(let reason):
            print("MeedyaDB: nothing sent — \(reason)")
        case .failed(let reason):
            print("MeedyaDB: FAILED — \(reason)")
        }
    }

    private static func describe(_ source: MusicBrainzDiscID.LeadOutSource) -> String {
        switch source {
        case .singleSession:
            return "the end of the disc (there is only one session)"
        case .reportedSession:
            return "the session table the drive reported"
        case .derivedFromDataTrack:
            return "where the data track starts, minus the standard session gap"
        }
    }
}

// MARK: - disc identify — JSON shape

/// The machine-readable form of an identification run. Written out by hand
/// rather than making the engine types `Encodable`, so the JSON contract
/// scripts depend on is owned here and can't drift when an engine type gains
/// a field.
private struct DiscIdentifyReport: Encodable {

    struct Identity: Encodable {
        var musicDiscId: String?
        var wholeDiscId: String?
        var leadOutSource: String?
        var tocFingerprint: String?
        var audioTrackCount: Int
        var isEnhancedCd: Bool
    }

    struct Match: Encodable {
        var musicBrainzReleaseId: String
        var title: String
        var artist: String?
        var date: String?
        var country: String?
        var trackCount: Int?
    }

    struct Contribution: Encodable {
        /// One of `succeeded`, `notAttempted`, `failed`.
        var status: String
        var reason: String?
        var discPublicId: String?
        var matched: Bool?
        var releasePublicId: String?
    }

    var identity: Identity
    var matches: [Match]
    var lookupFailure: String?
    var identified: Bool
    var summary: String
    var contribution: Contribution

    init(_ result: MusicDiscIdentificationResult) {
        identity = Identity(
            musicDiscId: result.identity.musicDiscID,
            wholeDiscId: result.identity.wholeDiscID,
            // Explicit closure types: a multi-statement closure whose body is
            // a switch is exactly the shape Swift's inference gives up on.
            leadOutSource: result.identity.leadOutSource.map { (source: MusicBrainzDiscID.LeadOutSource) -> String in
                switch source {
                case .singleSession: return "singleSession"
                case .reportedSession: return "reportedSession"
                case .derivedFromDataTrack: return "derivedFromDataTrack"
                }
            },
            tocFingerprint: result.identity.tocFingerprint,
            audioTrackCount: result.identity.audioTrackCount,
            isEnhancedCd: result.identity.isEnhancedCD
        )
        matches = result.matches.map { match in
            Match(
                musicBrainzReleaseId: match.id,
                title: match.title,
                artist: match.artist,
                date: match.date,
                country: match.country,
                trackCount: match.trackCount
            )
        }
        lookupFailure = result.lookupFailure
        identified = result.isIdentified
        summary = result.summary
        switch result.contribution {
        case .succeeded(let ingest):
            contribution = Contribution(
                status: "succeeded",
                reason: nil,
                discPublicId: ingest.discPublicId,
                matched: ingest.matched,
                releasePublicId: ingest.releasePublicId
            )
        case .notAttempted(let reason):
            contribution = Contribution(status: "notAttempted", reason: reason)
        case .failed(let reason):
            contribution = Contribution(status: "failed", reason: reason)
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
