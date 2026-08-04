// ============================================================================
// MeedyaConverter — CLI Serve Command
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import Foundation
import ConverterEngine

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run the REST API server for headless/remote encoding control (Issue #355).",
        discussion: """
            Starts `APIServer`, exposing POST /encode, POST /probe, GET \
            /status, GET /queue, and GET /profiles over HTTP on the given \
            port, backed by a real `EncodingEngine`.

            Authentication: every request must carry a matching \
            `Authorization: Bearer <api-key>` header — `APIServer` has no \
            unauthenticated mode, its bearer token is a required, non-optional \
            initialiser argument. If --api-key is not supplied, this command \
            generates a random one-time key and prints it to stderr at \
            startup; it is not shown again, and the server cannot be reached \
            without it.

            Known limitation (honestly surfaced by APIServer itself): \
            POST /encode enqueues jobs onto the real encoding queue but does \
            not start the queue runner, so encoding will not begin until \
            something else drives it — this command does not start one \
            either. This mirrors the desktop app's "Add to Queue" button \
            without "Start Queue".
            """
    )

    @Option(name: .customLong("port"), help: "TCP port to listen on.")
    var port: Int = 8484

    @Option(name: .customLong("api-key"), help: "Bearer token clients must send as 'Authorization: Bearer <key>'. If omitted, a random key is generated and printed to stderr once at startup.")
    var apiKey: String?

    func validate() throws {
        guard port > 0 && port <= 65535 else {
            throw ValidationError("--port must be between 1 and 65535.")
        }
        if let apiKey, apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("--api-key cannot be empty — APIServer requires every request to present it as a bearer token.")
        }
    }

    func run() async throws {
        let engine = EncodingEngine()
        try engine.configure()

        let resolvedKey: String
        if let apiKey {
            resolvedKey = apiKey
        } else {
            resolvedKey = UUID().uuidString
            printStderr("No --api-key supplied; generated one-time API key: \(resolvedKey)")
            printStderr("Save it now — it will not be printed again, and requests without it are rejected with 401.")
        }

        let server = APIServer(port: UInt16(port), apiKey: resolvedKey, engine: engine)

        do {
            try server.start()
        } catch {
            printStderr("Failed to start API server: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.generalError.rawValue)
        }

        printStderr("Serving on http://localhost:\(port) (all interfaces; APIServer has no --host binding option). Press Ctrl+C to stop.")

        // `APIServer.start()` binds the NWListener and returns immediately —
        // connections are handled asynchronously on its own internal
        // DispatchQueue, not by blocking this call. There is no `run()` or
        // `wait()` method to await, so this command keeps the process alive
        // with an effectively-infinite sleep; the process exits on SIGINT
        // (Ctrl+C) like any other long-running CLI server. `APIServer.stop()`
        // exists but nothing currently signals this loop to call it — a
        // future signal handler could do so gracefully.
        try await Task.sleep(nanoseconds: .max)
    }
}
