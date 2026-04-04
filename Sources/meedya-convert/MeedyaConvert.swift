// ============================================================================
// MeedyaConverter — CLI tool entry point
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import ConverterEngine

@main
struct MeedyaConvert: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meedya-convert",
        abstract: "Transcode, probe, and package media files.",
        discussion: """
            MeedyaConverter CLI — a professional media conversion tool for
            CI/CD pipelines, batch processing, and remote encoding.
            """,
        version: ConverterEngine.version,
        subcommands: [
            EncodeCommand.self,
            ProbeCommand.self,
            ProfilesCommand.self,
            BatchCommand.self,
        ]
    )
}
