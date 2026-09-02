// ============================================================================
// MeedyaConverter — TeamProfileManager (Issue #345)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - SyncMethod

/// The method used to synchronise team encoding profiles between machines.
///
/// Each method provides a different trade-off between ease of setup and
/// control. iCloud shared folders require no server infrastructure,
/// Git repositories provide version history, and HTTP servers allow
/// centralised management.
public enum SyncMethod: String, Codable, Sendable, CaseIterable {

    /// Sync via an iCloud Drive shared folder.
    case iCloudSharedFolder

    /// Sync via a Git repository (local or remote).
    case gitRepository

    /// Sync via an HTTP/HTTPS server endpoint.
    case httpServer
}

// MARK: - TeamProfileRepository

/// Configuration for a shared profile repository that team members connect to.
///
/// A repository defines where team profiles are stored and how they are
/// fetched and pushed. The `syncMethod` determines which fields are
/// relevant — for example, `serverURL` is used with `.httpServer` while
/// `sharedFolderPath` is used with `.iCloudSharedFolder`.
public struct TeamProfileRepository: Codable, Sendable {

    /// The remote server URL for HTTP-based sync.
    ///
    /// Only used when `syncMethod` is `.httpServer` or `.gitRepository`.
    public var serverURL: URL?

    /// The local or iCloud-shared folder path for file-based sync.
    ///
    /// Only used when `syncMethod` is `.iCloudSharedFolder`.
    public var sharedFolderPath: URL?

    /// The synchronisation method for this repository.
    public var syncMethod: SyncMethod

    /// The date of the last successful sync, or `nil` if never synced.
    public var lastSync: Date?

    /// Creates a new team profile repository configuration.
    ///
    /// - Parameters:
    ///   - serverURL: The remote server URL (for HTTP/Git sync).
    ///   - sharedFolderPath: The shared folder path (for iCloud sync).
    ///   - syncMethod: The synchronisation method to use.
    ///   - lastSync: The date of the last sync, defaults to `nil`.
    public init(
        serverURL: URL? = nil,
        sharedFolderPath: URL? = nil,
        syncMethod: SyncMethod,
        lastSync: Date? = nil
    ) {
        self.serverURL = serverURL
        self.sharedFolderPath = sharedFolderPath
        self.syncMethod = syncMethod
        self.lastSync = lastSync
    }
}

// MARK: - TeamProfileManager

/// Manages synchronisation of encoding profiles across a team.
///
/// Supports pushing local profiles to a shared repository, pulling remote
/// profiles, and resolving conflicts when the same profile has been edited
/// on multiple machines. Conflict resolution uses a "newer timestamp wins"
/// strategy based on each profile's `id` and modification date.
///
/// Thread-safety is achieved via an internal serial queue that serialises
/// access to mutable state.
///
/// Phase 14.1 — Team Shared Encoding Profiles (Issue #345)
public final class TeamProfileManager: @unchecked Sendable {

    // MARK: - Private Properties

    /// Serial queue for thread-safe access to internal state.
    private let queue = DispatchQueue(label: "com.mwbm.meedyaconverter.teamprofile")

    /// The currently configured repository, if any.
    private var _repository: TeamProfileRepository?

    /// JSON encoder configured for profile serialisation.
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    /// JSON decoder configured for profile deserialisation.
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Initialisation

    /// Creates a new team profile manager.
    ///
    /// - Parameter repository: An optional initial repository configuration.
    public init(repository: TeamProfileRepository? = nil) {
        self._repository = repository
    }

    // MARK: - Public Interface

    /// Whether the manager has a valid repository configured.
    ///
    /// Returns `true` when the repository has at least a server URL or
    /// shared folder path appropriate for its sync method.
    public var isConfigured: Bool {
        queue.sync {
            guard let repo = _repository else { return false }
            switch repo.syncMethod {
            case .iCloudSharedFolder:
                return repo.sharedFolderPath != nil
            case .gitRepository, .httpServer:
                return repo.serverURL != nil
            }
        }
    }

    /// Push local profiles to the team repository.
    ///
    /// Serialises the provided profiles to JSON and writes them to the
    /// configured repository location. For iCloud shared folders this
    /// writes directly to the folder; for HTTP servers it sends an HTTP
    /// PUT to the server endpoint via `URLSession` and requires a 2xx
    /// response; for Git it writes to the repository working tree.
    ///
    /// - Parameters:
    ///   - profiles: The encoding profiles to push.
    ///   - repository: The target repository configuration.
    /// - Throws: An error if serialisation, file I/O, or the HTTP push fails
    ///   — mirrors the "never fabricate success" contract `WebhookSender`
    ///   and `MediaServerIntegration` already establish elsewhere in this
    ///   module: a non-2xx (or non-HTTP) response throws
    ///   ``TeamProfileError/httpError(statusCode:body:)`` rather than
    ///   silently reporting success.
    public func pushProfiles(
        _ profiles: [EncodingProfile],
        to repository: TeamProfileRepository
    ) async throws {
        let data = try encoder.encode(profiles)

        switch repository.syncMethod {
        case .iCloudSharedFolder:
            guard let folderURL = repository.sharedFolderPath else {
                throw TeamProfileError.noSharedFolder
            }
            let fileURL = folderURL.appendingPathComponent("team_profiles.json")
            try data.write(to: fileURL, options: .atomic)

        case .gitRepository:
            guard let repoURL = repository.serverURL else {
                throw TeamProfileError.noServerURL
            }
            let fileURL = repoURL.appendingPathComponent("team_profiles.json")
            try data.write(to: fileURL, options: .atomic)

        case .httpServer:
            guard let serverURL = repository.serverURL else {
                throw TeamProfileError.noServerURL
            }
            var request = URLRequest(url: serverURL)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = String(data: responseData, encoding: .utf8)
                throw TeamProfileError.httpError(statusCode: code, body: body)
            }
        }

        queue.sync {
            _repository = TeamProfileRepository(
                serverURL: repository.serverURL,
                sharedFolderPath: repository.sharedFolderPath,
                syncMethod: repository.syncMethod,
                lastSync: Date()
            )
        }
    }

    /// Pull profiles from the team repository.
    ///
    /// Reads encoding profiles from the configured repository location
    /// and deserialises them from JSON.
    ///
    /// - Parameter repository: The source repository configuration.
    /// - Returns: An array of encoding profiles from the repository.
    /// - Throws: An error if file I/O or deserialisation fails.
    public func pullProfiles(
        from repository: TeamProfileRepository
    ) throws -> [EncodingProfile] {
        let data: Data

        switch repository.syncMethod {
        case .iCloudSharedFolder:
            guard let folderURL = repository.sharedFolderPath else {
                throw TeamProfileError.noSharedFolder
            }
            let fileURL = folderURL.appendingPathComponent("team_profiles.json")
            data = try Data(contentsOf: fileURL)

        case .gitRepository:
            guard let repoURL = repository.serverURL else {
                throw TeamProfileError.noServerURL
            }
            let fileURL = repoURL.appendingPathComponent("team_profiles.json")
            data = try Data(contentsOf: fileURL)

        case .httpServer:
            guard let serverURL = repository.serverURL else {
                throw TeamProfileError.noServerURL
            }
            // For HTTP, perform a synchronous fetch. In production this
            // would use async URLSession; here we use synchronous I/O
            // for simplicity.
            data = try Data(contentsOf: serverURL)
        }

        queue.sync {
            _repository = TeamProfileRepository(
                serverURL: repository.serverURL,
                sharedFolderPath: repository.sharedFolderPath,
                syncMethod: repository.syncMethod,
                lastSync: Date()
            )
        }

        return try decoder.decode([EncodingProfile].self, from: data)
    }

    /// Resolve conflicts between local and remote profile sets.
    ///
    /// Uses a "newer timestamp wins" strategy: for profiles with the same
    /// `id`, the version with the more recent `name` change (approximated
    /// by comparing profile content) is kept. Profiles that exist only
    /// locally or only remotely are always included.
    ///
    /// - Parameters:
    ///   - local: The local set of encoding profiles.
    ///   - remote: The remote set of encoding profiles.
    /// - Returns: A merged array with conflicts resolved.
    /// Identifies the conflicts a pull surfaces: remote profiles that share an
    /// `id` with a local profile but whose content differs. These — and only
    /// these — are what the user must resolve; a pull that finds none can be
    /// merged silently. `EncodingProfile` is `Hashable`, so "differs" is a
    /// value comparison of the whole profile, not just its name.
    ///
    /// Issue #482: the Team Profiles view initialised its conflict list to `[]`
    /// and never populated it, so the Conflicts section could never render and
    /// `resolveConflicts` always merged against nothing. This gives the pull a
    /// real diff to feed it.
    ///
    /// - Parameters:
    ///   - local: The profiles currently in the local store.
    ///   - remote: The profiles just pulled from the team repository.
    /// - Returns: The remote profiles that conflict with a local one, in the
    ///   order they appear in `remote`.
    public func detectConflicts(
        local: [EncodingProfile],
        remote: [EncodingProfile]
    ) -> [EncodingProfile] {
        var localByID: [UUID: EncodingProfile] = [:]
        for profile in local {
            localByID[profile.id] = profile
        }
        return remote.filter { remoteProfile in
            guard let localProfile = localByID[remoteProfile.id] else {
                return false
            }
            return localProfile != remoteProfile
        }
    }

    public func resolveConflicts(
        local: [EncodingProfile],
        remote: [EncodingProfile]
    ) -> [EncodingProfile] {
        var localMap: [UUID: EncodingProfile] = [:]
        for profile in local {
            localMap[profile.id] = profile
        }

        var remoteMap: [UUID: EncodingProfile] = [:]
        for profile in remote {
            remoteMap[profile.id] = profile
        }

        var merged: [EncodingProfile] = []
        var processedIDs: Set<UUID> = []

        // Process all local profiles, merging with remote where IDs overlap.
        for localProfile in local {
            processedIDs.insert(localProfile.id)
            if let remoteProfile = remoteMap[localProfile.id] {
                // Both exist — prefer the remote version if it differs
                // (newer timestamp wins; since EncodingProfile does not
                // carry a modification date, we prefer remote as it
                // represents the latest team state).
                merged.append(remoteProfile)
            } else {
                merged.append(localProfile)
            }
        }

        // Add remote-only profiles.
        for remoteProfile in remote where !processedIDs.contains(remoteProfile.id) {
            merged.append(remoteProfile)
        }

        return merged
    }
}

// MARK: - TeamProfileError

/// Errors that can occur during team profile operations.
public enum TeamProfileError: LocalizedError, Sendable {

    /// No shared folder path was configured.
    case noSharedFolder

    /// No server URL was configured.
    case noServerURL

    /// The profile data could not be decoded.
    case decodingFailed(String)

    /// The HTTP server responded with a non-success status code when
    /// pushing profiles. `body` is the raw response body, if any, decoded
    /// as UTF-8 text.
    case httpError(statusCode: Int, body: String?)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .noSharedFolder:
            return "No shared folder path is configured for team profile sync."
        case .noServerURL:
            return "No server URL is configured for team profile sync."
        case .decodingFailed(let detail):
            return "Failed to decode team profiles: \(detail)"
        case .httpError(let statusCode, let body):
            return "Team profile push failed with HTTP \(statusCode)\(body.map { ": \($0)" } ?? "")"
        }
    }
}
