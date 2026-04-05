// ============================================================================
// MeedyaConverter — CloudProfileSync
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides iCloud Drive-based synchronisation of encoding profiles across
// multiple Macs running MeedyaConverter.
//
// Features:
//   - Uploads encoding profiles to iCloud Drive (ubiquity container).
//   - Downloads profiles from iCloud Drive on other devices.
//   - Conflict resolution: newest modification date wins.
//   - Posts notifications when remote profiles change.
//   - Enable/disable toggle with persisted preference.
//   - Thread-safe with `@unchecked Sendable` and internal locking.
//
// Phase 12 — iCloud Drive Profile Sync (Issue #297)
// ---------------------------------------------------------------------------

import Foundation

// MARK: - CloudSyncStatus

/// Describes the current state of iCloud profile synchronisation.
public enum CloudSyncStatus: String, Codable, Sendable {
    /// Sync is disabled by the user.
    case disabled
    /// Sync is enabled and idle (no active transfer).
    case idle
    /// Profiles are currently being uploaded.
    case uploading
    /// Profiles are currently being downloaded.
    case downloading
    /// An error occurred during the last sync attempt.
    case error
    /// iCloud is not available on this device.
    case unavailable
}

// MARK: - CloudSyncConflict

/// Represents a conflict between a local and remote profile.
///
/// When both the local and remote copies of a profile have been modified
/// since the last sync, the caller can choose which version to keep.
public struct CloudSyncConflict: Identifiable, Sendable {

    /// The profile ID in conflict.
    public let id: UUID

    /// The local version of the profile.
    public var localProfile: EncodingProfile

    /// The remote (iCloud) version of the profile.
    public var remoteProfile: EncodingProfile

    /// Modification date of the local copy.
    public var localDate: Date

    /// Modification date of the remote copy.
    public var remoteDate: Date

    public init(
        id: UUID,
        localProfile: EncodingProfile,
        remoteProfile: EncodingProfile,
        localDate: Date,
        remoteDate: Date
    ) {
        self.id = id
        self.localProfile = localProfile
        self.remoteProfile = remoteProfile
        self.localDate = localDate
        self.remoteDate = remoteDate
    }
}

// MARK: - CloudProfileSync

/// Manages bidirectional synchronisation of encoding profiles via iCloud Drive.
///
/// Uses `FileManager.default.url(forUbiquityContainerIdentifier:)` to access
/// the app's iCloud Documents container. Profiles are stored as individual
/// JSON files named by their UUID, making merge and conflict detection
/// straightforward.
///
/// ### Conflict Resolution
/// By default, the newer profile (by modification date) wins. Callers can
/// inspect conflicts via ``conflicts`` and resolve them manually.
///
/// ### Notifications
/// Posts `CloudProfileSync.profilesDidChangeRemotely` when the iCloud
/// metadata query detects remote changes.
///
/// ### Thread Safety
/// All mutable state is protected by an `NSLock`. The class is marked
/// `@unchecked Sendable` because it manually synchronises access.
public final class CloudProfileSync: @unchecked Sendable {

    // MARK: - Notification Names

    /// Posted when remote profiles have changed in iCloud.
    public static let profilesDidChangeRemotely = Notification.Name(
        "com.mwbm.meedyaconverter.cloudProfilesDidChangeRemotely"
    )

    // MARK: - Properties

    /// Lock protecting all mutable state.
    private let lock = NSLock()

    /// Whether iCloud sync is currently enabled.
    private var _isSyncEnabled: Bool = false

    /// Current sync status.
    private var _status: CloudSyncStatus = .disabled

    /// Timestamp of the last successful sync.
    private var _lastSyncDate: Date?

    /// Detected conflicts from the most recent sync.
    private var _conflicts: [CloudSyncConflict] = []

    /// Metadata query for monitoring iCloud container changes.
    private var metadataQuery: NSMetadataQuery?

    /// The iCloud container URL, cached after first access.
    private var _containerURL: URL?

    /// Subfolder within the iCloud container for profiles.
    private static let profilesFolderName = "EncodingProfiles"

    // MARK: - Public Accessors

    /// Whether iCloud sync is enabled.
    public var isSyncEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSyncEnabled
    }

    /// Current sync status.
    public var status: CloudSyncStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    /// Timestamp of the last successful sync.
    public var lastSyncDate: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _lastSyncDate
    }

    /// Detected conflicts from the most recent sync.
    public var conflicts: [CloudSyncConflict] {
        lock.lock()
        defer { lock.unlock() }
        return _conflicts
    }

    // MARK: - Shared Instance

    /// Shared singleton instance.
    public static let shared = CloudProfileSync()

    // MARK: - Initialiser

    public init() {
        // Restore preference.
        _isSyncEnabled = UserDefaults.standard.bool(
            forKey: "cloudProfileSyncEnabled"
        )
        if _isSyncEnabled {
            _status = .idle
        }
    }

    // MARK: - Enable / Disable

    /// Enables iCloud profile synchronisation.
    ///
    /// Starts a metadata query to watch for remote changes in the iCloud
    /// container. Persists the preference to `UserDefaults`.
    public func enableSync() {
        lock.lock()
        _isSyncEnabled = true
        _status = .idle
        lock.unlock()

        UserDefaults.standard.set(true, forKey: "cloudProfileSyncEnabled")
        startMetadataQuery()
    }

    /// Disables iCloud profile synchronisation.
    ///
    /// Stops the metadata query and clears pending conflicts.
    public func disableSync() {
        lock.lock()
        _isSyncEnabled = false
        _status = .disabled
        _conflicts.removeAll()
        lock.unlock()

        UserDefaults.standard.set(false, forKey: "cloudProfileSyncEnabled")
        stopMetadataQuery()
    }

    // MARK: - Upload

    /// Uploads an array of encoding profiles to iCloud Drive.
    ///
    /// Each profile is written as an individual JSON file named
    /// `<UUID>.json` in the iCloud container's `EncodingProfiles` folder.
    /// Existing files for the same profile ID are overwritten.
    ///
    /// - Parameter profiles: The profiles to upload.
    /// - Throws: An error if the iCloud container is unavailable or
    ///   file writing fails.
    public func uploadProfiles(_ profiles: [EncodingProfile]) throws {
        guard let container = containerURL() else {
            lock.lock()
            _status = .unavailable
            lock.unlock()
            throw CloudSyncError.iCloudUnavailable
        }

        lock.lock()
        _status = .uploading
        lock.unlock()

        let profilesDir = container.appendingPathComponent(
            Self.profilesFolderName
        )
        try FileManager.default.createDirectory(
            at: profilesDir,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for profile in profiles {
            let fileURL = profilesDir.appendingPathComponent(
                "\(profile.id.uuidString).json"
            )
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
        }

        lock.lock()
        _status = .idle
        _lastSyncDate = Date()
        lock.unlock()
    }

    // MARK: - Download

    /// Downloads encoding profiles from iCloud Drive.
    ///
    /// Reads all `.json` files in the iCloud container's
    /// `EncodingProfiles` folder and decodes them as `EncodingProfile`.
    /// Files that cannot be decoded are silently skipped.
    ///
    /// - Returns: An array of profiles found in iCloud.
    /// - Throws: An error if the iCloud container is unavailable.
    public func downloadProfiles() throws -> [EncodingProfile] {
        guard let container = containerURL() else {
            lock.lock()
            _status = .unavailable
            lock.unlock()
            throw CloudSyncError.iCloudUnavailable
        }

        lock.lock()
        _status = .downloading
        lock.unlock()

        let profilesDir = container.appendingPathComponent(
            Self.profilesFolderName
        )

        guard FileManager.default.fileExists(atPath: profilesDir.path) else {
            lock.lock()
            _status = .idle
            _lastSyncDate = Date()
            lock.unlock()
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var profiles: [EncodingProfile] = []

        let contents = try FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: nil
        )

        for fileURL in contents where fileURL.pathExtension == "json" {
            if let data = try? Data(contentsOf: fileURL),
               let profile = try? decoder.decode(
                   EncodingProfile.self,
                   from: data
               ) {
                profiles.append(profile)
            }
        }

        lock.lock()
        _status = .idle
        _lastSyncDate = Date()
        lock.unlock()

        return profiles
    }

    // MARK: - Conflict Resolution

    /// Resolves a conflict by choosing the local or remote version.
    ///
    /// - Parameters:
    ///   - conflictId: The profile ID to resolve.
    ///   - keepLocal: If `true`, the local version is kept and uploaded
    ///     to iCloud. If `false`, the remote version is returned for
    ///     the caller to save locally.
    /// - Returns: The winning profile.
    public func resolveConflict(
        conflictId: UUID,
        keepLocal: Bool
    ) -> EncodingProfile? {
        lock.lock()
        guard let index = _conflicts.firstIndex(where: {
            $0.id == conflictId
        }) else {
            lock.unlock()
            return nil
        }
        let conflict = _conflicts.remove(at: index)
        lock.unlock()

        return keepLocal ? conflict.localProfile : conflict.remoteProfile
    }

    /// Automatically resolves all conflicts by keeping the newer version
    /// (based on modification date).
    ///
    /// - Returns: An array of the winning profiles.
    public func resolveAllConflictsNewerWins() -> [EncodingProfile] {
        lock.lock()
        let currentConflicts = _conflicts
        _conflicts.removeAll()
        lock.unlock()

        return currentConflicts.map { conflict in
            conflict.localDate >= conflict.remoteDate
                ? conflict.localProfile
                : conflict.remoteProfile
        }
    }

    // MARK: - Private Helpers

    /// Returns the iCloud ubiquity container URL, or `nil` if iCloud
    /// is not available.
    private func containerURL() -> URL? {
        lock.lock()
        if let cached = _containerURL {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let url = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        )

        if let url {
            lock.lock()
            _containerURL = url
            lock.unlock()
        }

        return url
    }

    /// Starts an `NSMetadataQuery` to monitor the iCloud container for
    /// changes made on other devices.
    private func startMetadataQuery() {
        stopMetadataQuery()

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K LIKE '*.json'",
            NSMetadataItemFSNameKey
        )

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.handleRemoteChange()
        }

        lock.lock()
        metadataQuery = query
        lock.unlock()

        query.start()
    }

    /// Stops the active metadata query.
    private func stopMetadataQuery() {
        lock.lock()
        let query = metadataQuery
        metadataQuery = nil
        lock.unlock()

        query?.stop()
    }

    /// Called when the metadata query detects remote changes.
    private func handleRemoteChange() {
        NotificationCenter.default.post(
            name: Self.profilesDidChangeRemotely,
            object: nil
        )
    }
}

// MARK: - CloudSyncError

/// Errors that can occur during iCloud profile synchronisation.
public enum CloudSyncError: Error, LocalizedError, Sendable {
    /// iCloud is not available on this device (not signed in or restricted).
    case iCloudUnavailable
    /// Failed to read or write profile data.
    case dataError(String)

    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not available. Please sign in to iCloud in System Settings."
        case .dataError(let detail):
            return "Profile sync data error: \(detail)"
        }
    }
}
