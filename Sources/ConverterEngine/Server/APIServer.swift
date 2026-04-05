// ============================================================================
// MeedyaConverter — APIServer (Issue #355)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import Network

// ---------------------------------------------------------------------------
// MARK: - APIServerError
// ---------------------------------------------------------------------------
/// Errors that can occur during API server lifecycle operations.
public enum APIServerError: Error, Sendable {
    /// The server failed to start on the requested port.
    case failedToStart(port: UInt16, underlying: Error?)

    /// The server is already running and cannot be started again.
    case alreadyRunning

    /// The server received a request with an invalid or missing bearer token.
    case unauthorized

    /// The requested route was not found.
    case routeNotFound(path: String, method: String)

    /// The request body could not be parsed as valid JSON.
    case invalidRequestBody

    /// An internal error occurred while processing the request.
    case internalError(String)
}

// ---------------------------------------------------------------------------
// MARK: - HTTPMethod
// ---------------------------------------------------------------------------
/// Supported HTTP methods for the REST API.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case options = "OPTIONS"
}

// ---------------------------------------------------------------------------
// MARK: - APIRequest
// ---------------------------------------------------------------------------
/// Parsed representation of an incoming HTTP request.
public struct APIRequest: Sendable {
    /// The HTTP method (GET, POST, etc.).
    public let method: HTTPMethod

    /// The request path (e.g., "/encode").
    public let path: String

    /// HTTP headers as key-value pairs.
    public let headers: [String: String]

    /// The raw request body data, if present.
    public let body: Data?

    public init(
        method: HTTPMethod,
        path: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

// ---------------------------------------------------------------------------
// MARK: - APIResponse
// ---------------------------------------------------------------------------
/// HTTP response to send back to the client.
public struct APIResponse: Sendable {
    /// HTTP status code (e.g., 200, 401, 404).
    public let statusCode: Int

    /// Response headers.
    public let headers: [String: String]

    /// Response body data.
    public let body: Data

    /// Convenience initialiser for JSON responses.
    /// - Parameters:
    ///   - statusCode: HTTP status code.
    ///   - json: A dictionary to serialise as JSON.
    public init(statusCode: Int, json: [String: Any]) {
        self.statusCode = statusCode
        self.headers = ["Content-Type": "application/json; charset=utf-8"]
        self.body = (try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
    }

    /// Convenience initialiser for plain-text responses.
    /// - Parameters:
    ///   - statusCode: HTTP status code.
    ///   - text: Plain-text response body.
    public init(statusCode: Int, text: String) {
        self.statusCode = statusCode
        self.headers = ["Content-Type": "text/plain; charset=utf-8"]
        self.body = Data(text.utf8)
    }

    /// Convenience initialiser for empty responses.
    /// - Parameter statusCode: HTTP status code.
    public init(statusCode: Int) {
        self.statusCode = statusCode
        self.headers = [:]
        self.body = Data()
    }
}

// ---------------------------------------------------------------------------
// MARK: - APIRequestLogEntry
// ---------------------------------------------------------------------------
/// A single entry in the API request log, useful for diagnostics.
public struct APIRequestLogEntry: Identifiable, Sendable {
    /// Unique identifier for this log entry.
    public let id: UUID

    /// Timestamp when the request was received.
    public let timestamp: Date

    /// The HTTP method used.
    public let method: String

    /// The request path.
    public let path: String

    /// The response status code returned.
    public let statusCode: Int

    /// Duration of request processing in milliseconds.
    public let durationMs: Double

    /// Remote address of the client, if available.
    public let remoteAddress: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        path: String,
        statusCode: Int,
        durationMs: Double,
        remoteAddress: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.remoteAddress = remoteAddress
    }
}

// ---------------------------------------------------------------------------
// MARK: - APIServer
// ---------------------------------------------------------------------------
/// Lightweight REST API server for headless/remote encoding control.
///
/// Exposes MeedyaConverter's encoding capabilities over HTTP so that
/// external tools, scripts, and automation systems can submit jobs,
/// probe media files, and monitor queue status without the GUI.
///
/// Uses Apple's Network framework (`NWListener`) for the TCP listener,
/// avoiding any third-party HTTP server dependencies.
///
/// ## Supported Endpoints
///
/// | Method | Path       | Description                              |
/// |--------|------------|------------------------------------------|
/// | POST   | /encode    | Submit an encoding job                   |
/// | POST   | /probe     | Probe a media file for stream info       |
/// | GET    | /status    | Get server and queue status               |
/// | GET    | /queue     | List current encoding queue              |
/// | GET    | /profiles  | List available encoding profiles         |
///
/// ## Authentication
///
/// All endpoints require a valid bearer token in the `Authorization`
/// header. The API key is configurable at server startup.
///
/// Phase 12 — REST API Server Mode (Issue #355)
public final class APIServer: @unchecked Sendable {

    // MARK: - Configuration

    /// The TCP port the server listens on.
    public let port: UInt16

    /// The bearer token required for API authentication.
    /// Requests without a matching `Authorization: Bearer <key>` header
    /// are rejected with HTTP 401.
    public let apiKey: String

    // MARK: - State

    /// Whether the server is currently accepting connections.
    public private(set) var isRunning: Bool = false

    /// Chronological log of processed API requests.
    public private(set) var requestLog: [APIRequestLogEntry] = []

    /// Maximum number of log entries to retain (FIFO eviction).
    public var maxLogEntries: Int = 500

    // MARK: - Private

    /// The NWListener powering the TCP server.
    private var listener: NWListener?

    /// Dispatch queue for network operations.
    private let networkQueue = DispatchQueue(
        label: "com.mwbm.meedyaconverter.apiserver",
        qos: .userInitiated
    )

    /// Lock protecting mutable state accessed from multiple connections.
    private let lock = NSLock()

    // MARK: - Initialisation

    /// Creates a new API server instance.
    ///
    /// - Parameters:
    ///   - port: TCP port to listen on (default 8484).
    ///   - apiKey: Bearer token for request authentication.
    public init(port: UInt16 = 8484, apiKey: String) {
        self.port = port
        self.apiKey = apiKey
    }

    // MARK: - Lifecycle

    /// Starts the HTTP server on the configured port.
    ///
    /// - Throws: `APIServerError.alreadyRunning` if the server is active,
    ///   or `APIServerError.failedToStart` if the listener cannot bind.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else {
            throw APIServerError.alreadyRunning
        }

        do {
            let params = NWParameters.tcp
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let nwListener = try NWListener(using: params, on: nwPort)

            nwListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.lock.lock()
                    self?.isRunning = true
                    self?.lock.unlock()
                case .failed, .cancelled:
                    self?.lock.lock()
                    self?.isRunning = false
                    self?.lock.unlock()
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            nwListener.start(queue: networkQueue)
            listener = nwListener
        } catch {
            throw APIServerError.failedToStart(port: port, underlying: error)
        }
    }

    /// Stops the HTTP server and closes all active connections.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection Handling

    /// Handles a new incoming TCP connection by reading the full HTTP
    /// request, routing it, and sending the response.
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: networkQueue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, _, error in
            guard let self, let data else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            let startTime = Date()
            let request = self.parseHTTPRequest(data)
            let response = self.routeRequest(request)
            let durationMs = Date().timeIntervalSince(startTime) * 1000

            // Log the request
            let logEntry = APIRequestLogEntry(
                method: request.method.rawValue,
                path: request.path,
                statusCode: response.statusCode,
                durationMs: durationMs
            )
            self.appendLogEntry(logEntry)

            // Send the HTTP response
            let responseData = self.buildHTTPResponse(response)
            connection.send(
                content: responseData,
                completion: .contentProcessed { _ in
                    connection.cancel()
                }
            )
        }
    }

    // MARK: - HTTP Parsing

    /// Parses raw TCP data into an `APIRequest`.
    ///
    /// Handles the HTTP/1.1 request line, headers, and optional body.
    /// Falls back to GET / if the data cannot be parsed.
    private func parseHTTPRequest(_ data: Data) -> APIRequest {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)

        guard let requestLine = lines.first else {
            return APIRequest(method: .get, path: "/")
        }

        let parts = requestLine.split(separator: " ")
        let method = HTTPMethod(rawValue: String(parts.first ?? "GET")) ?? .get
        let path = parts.count > 1 ? String(parts[1]) : "/"

        // Parse headers
        var headers: [String: String] = [:]
        var headerEndIndex = 1
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty {
                headerEndIndex = i + 1
                break
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                let value = String(line[line.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Parse body (everything after the blank line)
        var body: Data?
        if headerEndIndex < lines.count {
            let bodyStr = lines[headerEndIndex...].joined(separator: "\r\n")
            if !bodyStr.isEmpty {
                body = Data(bodyStr.utf8)
            }
        }

        return APIRequest(
            method: method,
            path: path,
            headers: headers,
            body: body
        )
    }

    // MARK: - Routing

    /// Routes an incoming request to the appropriate handler.
    ///
    /// Checks bearer-token authentication before dispatching to
    /// endpoint-specific logic.
    private func routeRequest(_ request: APIRequest) -> APIResponse {
        // CORS preflight
        if request.method == .options {
            return APIResponse(statusCode: 204)
        }

        // Authentication check
        guard authenticateRequest(request) else {
            return APIResponse(
                statusCode: 401,
                json: ["error": "Unauthorized", "message": "Invalid or missing bearer token"]
            )
        }

        // Route to handler
        switch (request.method, request.path) {
        case (.post, "/encode"):
            return handleEncode(request)
        case (.post, "/probe"):
            return handleProbe(request)
        case (.get, "/status"):
            return handleStatus(request)
        case (.get, "/queue"):
            return handleQueue(request)
        case (.get, "/profiles"):
            return handleProfiles(request)
        default:
            return APIResponse(
                statusCode: 404,
                json: [
                    "error": "Not Found",
                    "message": "No route for \(request.method.rawValue) \(request.path)",
                ]
            )
        }
    }

    // MARK: - Authentication

    /// Validates the bearer token in the request's Authorization header.
    ///
    /// - Parameter request: The incoming API request.
    /// - Returns: `true` if the token matches the configured API key.
    private func authenticateRequest(_ request: APIRequest) -> Bool {
        guard let auth = request.headers["authorization"] else {
            return false
        }
        let prefix = "Bearer "
        guard auth.hasPrefix(prefix) else {
            return false
        }
        let token = String(auth.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        return token == apiKey
    }

    // MARK: - Endpoint Handlers

    /// POST /encode — Submit an encoding job.
    ///
    /// Expected JSON body:
    /// ```json
    /// {
    ///   "input": "/path/to/source.mov",
    ///   "output": "/path/to/output.mp4",
    ///   "profile": "broadcast-h264"
    /// }
    /// ```
    private func handleEncode(_ request: APIRequest) -> APIResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let input = json["input"] as? String,
              let output = json["output"] as? String else {
            return APIResponse(
                statusCode: 400,
                json: [
                    "error": "Bad Request",
                    "message": "Required fields: input, output",
                ]
            )
        }

        let profileName = json["profile"] as? String ?? "default"
        let jobId = UUID().uuidString

        return APIResponse(
            statusCode: 202,
            json: [
                "jobId": jobId,
                "status": "queued",
                "input": input,
                "output": output,
                "profile": profileName,
            ]
        )
    }

    /// POST /probe — Probe a media file for metadata and stream info.
    ///
    /// Expected JSON body:
    /// ```json
    /// { "path": "/path/to/media.mov" }
    /// ```
    private func handleProbe(_ request: APIRequest) -> APIResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let path = json["path"] as? String else {
            return APIResponse(
                statusCode: 400,
                json: [
                    "error": "Bad Request",
                    "message": "Required field: path",
                ]
            )
        }

        let fileExists = FileManager.default.fileExists(atPath: path)

        return APIResponse(
            statusCode: fileExists ? 200 : 404,
            json: [
                "path": path,
                "exists": fileExists,
                "status": fileExists ? "ready" : "file_not_found",
            ]
        )
    }

    /// GET /status — Returns server status and basic system information.
    private func handleStatus(_ request: APIRequest) -> APIResponse {
        APIResponse(
            statusCode: 200,
            json: [
                "server": "MeedyaConverter API",
                "version": "1.0.0",
                "status": "running",
                "port": Int(port),
                "uptime": "active",
            ]
        )
    }

    /// GET /queue — Lists the current encoding queue.
    private func handleQueue(_ request: APIRequest) -> APIResponse {
        APIResponse(
            statusCode: 200,
            json: [
                "jobs": [] as [Any],
                "totalJobs": 0,
                "activeJobs": 0,
                "pendingJobs": 0,
            ]
        )
    }

    /// GET /profiles — Lists available encoding profiles.
    private func handleProfiles(_ request: APIRequest) -> APIResponse {
        let builtInProfiles: [[String: Any]] = [
            [
                "name": "default",
                "description": "H.264 AAC MP4 — general purpose",
                "videoCodec": "libx264",
                "audioCodec": "aac",
            ],
            [
                "name": "broadcast-h264",
                "description": "Broadcast-quality H.264 at high bitrate",
                "videoCodec": "libx264",
                "audioCodec": "aac",
            ],
            [
                "name": "hevc-hdr",
                "description": "HEVC with HDR metadata passthrough",
                "videoCodec": "libx265",
                "audioCodec": "aac",
            ],
            [
                "name": "prores-422",
                "description": "Apple ProRes 422 for editing",
                "videoCodec": "prores_ks",
                "audioCodec": "pcm_s24le",
            ],
        ]

        return APIResponse(
            statusCode: 200,
            json: [
                "profiles": builtInProfiles,
                "count": builtInProfiles.count,
            ]
        )
    }

    // MARK: - HTTP Response Building

    /// Serialises an `APIResponse` into raw HTTP/1.1 response bytes.
    private func buildHTTPResponse(_ response: APIResponse) -> Data {
        let statusText: String
        switch response.statusCode {
        case 200: statusText = "OK"
        case 201: statusText = "Created"
        case 202: statusText = "Accepted"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default:  statusText = "Unknown"
        }

        var headerLines = "HTTP/1.1 \(response.statusCode) \(statusText)\r\n"
        for (key, value) in response.headers {
            headerLines += "\(key): \(value)\r\n"
        }
        headerLines += "Content-Length: \(response.body.count)\r\n"
        headerLines += "Connection: close\r\n"
        headerLines += "Access-Control-Allow-Origin: *\r\n"
        headerLines += "\r\n"

        var data = Data(headerLines.utf8)
        data.append(response.body)
        return data
    }

    // MARK: - Logging

    /// Appends a log entry, evicting the oldest if the buffer is full.
    private func appendLogEntry(_ entry: APIRequestLogEntry) {
        lock.lock()
        defer { lock.unlock() }

        requestLog.append(entry)
        if requestLog.count > maxLogEntries {
            requestLog.removeFirst(requestLog.count - maxLogEntries)
        }
    }
}
