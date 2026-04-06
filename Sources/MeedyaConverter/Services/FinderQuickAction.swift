// ============================================================================
// MeedyaConverter — FinderQuickAction
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides macOS Services menu integration and "Open With" handling for
// MeedyaConverter. Registers the app as a Services provider so users can
// right-click media files in Finder and choose "Convert with MeedyaConverter"
// or "Analyze with MeedyaConverter".
//
// A full Finder extension (FinderSync) requires a separate app-extension
// target with its own bundle identifier and entitlements. This file creates
// the action-handling logic that sits inside the main app, responding to
// Services invocations and document-open requests.
//
// ### Services Menu Items
//   - "Convert with MeedyaConverter" — import files and start encoding
//     with the default profile.
//   - "Analyze with MeedyaConverter" — import files for inspection only
//     (no encoding triggered).
//
// ### Open With
// Document types declared in Info.plist allow the app to appear in the
// "Open With" context menu. When files are opened this way, macOS delivers
// them through the standard `NSApplication` delegate or SwiftUI `onOpenURL`
// handler. This class provides helpers that parse and route those URLs.
//
// Phase 11 — Quick Actions / Finder Extension (Issue #283)
// ---------------------------------------------------------------------------

import AppKit
import UniformTypeIdentifiers

// MARK: - FinderQuickAction

/// Handles macOS Services menu invocations and document-open routing.
///
/// Register this class as the Services provider at app launch via
/// ``registerAsService()``. The system will then route pasteboard data
/// from Finder's right-click Services submenu through
/// ``handleServiceInput(pasteboard:userData:error:)``.
///
/// - Note: This class is `@MainActor` because it accesses AppKit types
///   (`NSPasteboard`, `NSApplication`) and coordinates with the main-thread
///   `AppViewModel`.
///
/// - Important: A full Finder Sync extension requires a separate target.
///   This class implements the in-app side of Services integration only.
@MainActor
final class FinderQuickAction: NSObject {

    // MARK: - Service User Data Keys

    /// User data string passed by the "Convert" service menu item.
    static let convertUserData = "Ltd.MWBMpartners.MeedyaConverter.convert"

    /// User data string passed by the "Analyze" service menu item.
    static let analyzeUserData = "Ltd.MWBMpartners.MeedyaConverter.analyze"

    // MARK: - Supported Types

    /// The UTTypes accepted from the Services pasteboard.
    ///
    /// Matches the document types declared in Info.plist so that only
    /// media files the app can actually process are accepted.
    private static let supportedTypes: [UTType] = [
        .movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .avi,
        .mpeg2Video, .mp3, .wav, .aiff
    ]

    // MARK: - Registration

    /// Register the application as a macOS Services provider.
    ///
    /// Call this once during app launch (e.g., in `MeedyaConverterApp.onAppear`).
    /// After registration, the system discovers the app's `NSServices` entries
    /// from Info.plist and wires pasteboard data to ``handleServiceInput``.
    ///
    /// The Info.plist must declare `NSServices` entries with:
    /// - `NSMessage`: `handleServiceInput`
    /// - `NSSendTypes`: `NSFilenamesPboardType` / `public.file-url`
    /// - `NSMenuItem`: the localised menu title
    /// - `NSUserData`: one of ``convertUserData`` or ``analyzeUserData``
    static func registerAsService() {
        let provider = FinderQuickAction()
        NSApp.registerServicesMenuSendTypes(
            [.fileURL, .string],
            returnTypes: []
        )
        NSApp.servicesProvider = provider
    }

    // MARK: - Service Handler

    /// Handle incoming file data from the macOS Services menu.
    ///
    /// The system invokes this method when the user selects "Convert with
    /// MeedyaConverter" or "Analyze with MeedyaConverter" from Finder's
    /// Services submenu. The `userData` string distinguishes the two actions.
    ///
    /// - Parameters:
    ///   - pasteboard: The pasteboard containing the selected file URLs.
    ///   - userData: A string identifying which service was invoked
    ///     (``convertUserData`` or ``analyzeUserData``).
    ///   - error: An out-parameter for reporting errors back to the system.
    @objc func handleServiceInput(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        // Extract file URLs from the pasteboard
        let urls = extractFileURLs(from: pasteboard)

        guard !urls.isEmpty else {
            error.pointee = "No supported media files found in selection." as NSString
            return
        }

        // Bring the app to the foreground
        NSApp.activate(ignoringOtherApps: true)

        // Determine the action based on userData
        let shouldEncode = (userData == Self.convertUserData)

        // Post a notification so AppViewModel can pick up the files
        NotificationCenter.default.post(
            name: .finderQuickActionFilesReceived,
            object: nil,
            userInfo: [
                FinderQuickActionUserInfoKey.urls: urls,
                FinderQuickActionUserInfoKey.shouldEncode: shouldEncode
            ]
        )
    }

    // MARK: - Open With Handling

    /// Parse file URLs from an "Open With" launch or reopen event.
    ///
    /// Call this from the SwiftUI `onOpenURL` handler or `NSApplicationDelegate`
    /// to convert incoming file URLs into importable media files.
    ///
    /// - Parameter urls: File URLs passed by the system when the user opens
    ///   files with this app.
    /// - Returns: An array of validated, accessible file URLs. URLs that
    ///   cannot be read or do not match supported types are filtered out.
    static func filterSupportedURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            guard url.isFileURL else { return false }
            guard FileManager.default.isReadableFile(atPath: url.path) else { return false }

            // Check if the file's UTType matches any supported type
            if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
               let contentType = resourceValues.contentType {
                return supportedTypes.contains { contentType.conforms(to: $0) }
            }

            // Fall back to extension-based check for common media extensions
            let mediaExtensions: Set<String> = [
                "mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv", "webm",
                "mpg", "mpeg", "ts", "m2ts", "mts", "vob",
                "mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg", "wma", "opus"
            ]
            return mediaExtensions.contains(url.pathExtension.lowercased())
        }
    }

    // MARK: - Pasteboard Parsing

    /// Extract file URLs from an `NSPasteboard`.
    ///
    /// Handles both `fileURL` pasteboard type (modern) and legacy filename
    /// arrays for backwards compatibility with older Finder versions.
    ///
    /// - Parameter pasteboard: The Services pasteboard to read from.
    /// - Returns: An array of file URLs, filtered to supported media types.
    private func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        // Modern: read file URLs directly
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            urls.append(contentsOf: fileURLs)
        }

        // Legacy fallback: read filenames as strings
        if urls.isEmpty, let filenames = pasteboard.propertyList(
            forType: .init("NSFilenamesPboardType")
        ) as? [String] {
            let fileURLsFromNames = filenames.map { URL(fileURLWithPath: $0) }
            urls.append(contentsOf: fileURLsFromNames)
        }

        return Self.filterSupportedURLs(urls)
    }
}

// MARK: - Notification Names

extension Notification.Name {

    /// Posted when the Finder quick action receives files from the Services menu.
    ///
    /// The `userInfo` dictionary contains:
    /// - ``FinderQuickActionUserInfoKey/urls``: `[URL]` — the received file URLs.
    /// - ``FinderQuickActionUserInfoKey/shouldEncode``: `Bool` — whether to
    ///   start encoding immediately with the default profile.
    static let finderQuickActionFilesReceived = Notification.Name(
        "Ltd.MWBMpartners.MeedyaConverter.finderQuickActionFilesReceived"
    )
}

// MARK: - User Info Keys

/// Keys for the ``Notification.Name.finderQuickActionFilesReceived`` notification.
enum FinderQuickActionUserInfoKey {
    /// Key for the `[URL]` array of received file URLs.
    static let urls = "urls"

    /// Key for the `Bool` flag indicating whether encoding should start automatically.
    static let shouldEncode = "shouldEncode"
}
