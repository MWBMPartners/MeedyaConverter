// ============================================================================
// MeedyaConverter — MetadataHTTPClient
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MetadataHTTPClient

/// Abstraction over "send one HTTP request", so metadata lookups can be
/// unit-tested with canned responses (`MusicBrainzMockHTTPClient` in
/// `MusicBrainzLookupServiceTests`) and never hit the network in CI.
/// `URLSessionMetadataHTTPClient` is the production conformer.
public protocol MetadataHTTPClient: Sendable {
    /// Send `request` and return the body plus the HTTP response.
    /// - Throws: Any transport error (`URLError` from `URLSession`, or
    ///   `MetadataHTTPClientError.nonHTTPResponse`). Cancellation surfaces as
    ///   `URLError.cancelled` from `URLSession`; callers normalise it.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// MARK: - MetadataHTTPClientError

public enum MetadataHTTPClientError: Error, Sendable, Equatable, LocalizedError {
    case nonHTTPResponse

    public var errorDescription: String? {
        "The server returned a response that was not an HTTP response."
    }
}

// MARK: - URLSessionMetadataHTTPClient

/// The production `MetadataHTTPClient` conformer, backed by a real
/// `URLSession`.
public struct URLSessionMetadataHTTPClient: MetadataHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MetadataHTTPClientError.nonHTTPResponse
        }
        return (data, http)
    }
}
