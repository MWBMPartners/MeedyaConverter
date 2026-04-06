// ============================================================================
// MeedyaConverter — HandoffManager (Issue #362)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import AppKit
import ConverterEngine

// MARK: - HandoffManager

/// Manages Handoff / Continuity for encoding configuration sharing between devices.
///
/// Uses `NSUserActivity` to advertise the current encoding profile so a second Mac
/// (or future iOS companion) can resume exactly where the user left off.
///
/// Phase 13 — Handoff / Continuity (Issue #362)
@MainActor
@Observable
final class HandoffManager {

    // MARK: - Constants

    /// The activity type registered in Info.plist for Handoff eligibility.
    static let activityType = "Ltd.MWBMpartners.MeedyaConverter.encoding-config"

    // MARK: - UserInfo Keys

    /// Keys stored in the `NSUserActivity.userInfo` dictionary.
    private enum UserInfoKey {
        static let profileName      = "profileName"
        static let videoCodec       = "videoCodec"
        static let audioCodec       = "audioCodec"
        static let containerFormat  = "containerFormat"
        static let videoCRF         = "videoCRF"
        static let videoBitrate     = "videoBitrate"
        static let audioPassthrough = "audioPassthrough"
        static let fileURL          = "fileURL"
    }

    // MARK: - Properties

    /// The currently advertised user activity, if any.
    var currentActivity: NSUserActivity?

    // MARK: - Create Activity

    /// Creates and configures an `NSUserActivity` representing the given encoding
    /// profile and optional source file URL.
    ///
    /// - Parameters:
    ///   - profile: The encoding profile whose settings should be transferred.
    ///   - fileURL: An optional file URL for the source media (bookmarked for Handoff).
    /// - Returns: A configured `NSUserActivity` ready for Handoff advertising.
    func createActivity(profile: EncodingProfile, fileURL: URL?) -> NSUserActivity {
        let activity = NSUserActivity(activityType: Self.activityType)
        activity.title = "Encoding Config — \(profile.name)"
        activity.isEligibleForHandoff = true
        activity.needsSave = true

        var info: [String: Any] = [
            UserInfoKey.profileName:      profile.name,
            UserInfoKey.containerFormat:  profile.containerFormat.rawValue,
            UserInfoKey.audioPassthrough: profile.audioPassthrough
        ]

        if let videoCodec = profile.videoCodec {
            info[UserInfoKey.videoCodec] = videoCodec.rawValue
        }
        if let audioCodec = profile.audioCodec {
            info[UserInfoKey.audioCodec] = audioCodec.rawValue
        }
        if let crf = profile.videoCRF {
            info[UserInfoKey.videoCRF] = crf
        }
        if let bitrate = profile.videoBitrate {
            info[UserInfoKey.videoBitrate] = bitrate
        }
        if let url = fileURL {
            info[UserInfoKey.fileURL] = url.absoluteString
        }

        activity.userInfo = info
        activity.becomeCurrent()
        currentActivity = activity
        return activity
    }

    // MARK: - Handle Incoming Activity

    /// Processes an incoming `NSUserActivity` received via Handoff from another device.
    ///
    /// Extracts profile name, codec, container, and quality settings from `userInfo`
    /// and logs the restoration. The caller is responsible for applying these values
    /// to the active encoding session.
    ///
    /// - Parameter activity: The incoming `NSUserActivity` from Handoff.
    func handleIncomingActivity(_ activity: NSUserActivity) {
        guard activity.activityType == Self.activityType,
              let info = activity.userInfo else { return }

        let profileName     = info[UserInfoKey.profileName] as? String ?? "Unknown"
        let videoCodecRaw   = info[UserInfoKey.videoCodec] as? String
        let audioCodecRaw   = info[UserInfoKey.audioCodec] as? String
        let containerRaw    = info[UserInfoKey.containerFormat] as? String
        let crf             = info[UserInfoKey.videoCRF] as? Int
        let bitrate         = info[UserInfoKey.videoBitrate] as? Int
        let audioPassthrough = info[UserInfoKey.audioPassthrough] as? Bool ?? false
        let fileURLString   = info[UserInfoKey.fileURL] as? String

        // Log restoration details for diagnostics.
        var components: [String] = ["profile=\(profileName)"]
        if let vc = videoCodecRaw   { components.append("videoCodec=\(vc)") }
        if let ac = audioCodecRaw   { components.append("audioCodec=\(ac)") }
        if let ct = containerRaw    { components.append("container=\(ct)") }
        if let c  = crf             { components.append("crf=\(c)") }
        if let b  = bitrate         { components.append("bitrate=\(b)") }
        components.append("audioPassthrough=\(audioPassthrough)")
        if let f = fileURLString    { components.append("file=\(f)") }

        // Store incoming activity for external consumers.
        currentActivity = activity

        #if DEBUG
        print("[HandoffManager] Received Handoff: \(components.joined(separator: ", "))")
        #endif
    }

    // MARK: - Invalidation

    /// Stops advertising the current Handoff activity.
    func invalidateCurrentActivity() {
        currentActivity?.invalidate()
        currentActivity = nil
    }
}
