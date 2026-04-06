// ============================================================================
// MeedyaConverter — NotificationActionHandler
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Implements interactive macOS notifications with action buttons for
// MeedyaConverter. When an encoding job completes, fails, or the entire
// queue finishes, the notification banner includes contextual action
// buttons (e.g., "Open in Finder", "Retry", "View Log").
//
// ### Notification Categories
//   - `ENCODE_COMPLETE`: "Open in Finder", "Start Next"
//   - `ENCODE_FAILED`: "View Log", "Retry"
//   - `QUEUE_COMPLETE`: "Open Output Folder"
//
// ### Integration
// Set this handler as the `UNUserNotificationCenter` delegate at app
// launch, before any notifications are posted. Call `registerCategories()`
// to declare action definitions with the notification centre.
//
// Phase 11 — Interactive Notifications with Actions (Issue #361)
// ---------------------------------------------------------------------------

import AppKit
import UserNotifications

// MARK: - NotificationActionHandler

/// Handles interactive notification actions for encoding status notifications.
///
/// Conforms to `UNUserNotificationCenterDelegate` to receive action taps
/// when the user interacts with notification banners. Routes each action
/// to the appropriate `AppViewModel` method or system operation.
///
/// - Note: This class is `@MainActor` because it posts UI-driving updates
///   and accesses `NSWorkspace` which must be called on the main thread.
@MainActor
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Category Identifiers

    /// Notification category for a successfully completed encoding job.
    static let encodeCompleteCategory = "ENCODE_COMPLETE"

    /// Notification category for a failed encoding job.
    static let encodeFailedCategory = "ENCODE_FAILED"

    /// Notification category for when the entire queue has finished.
    static let queueCompleteCategory = "QUEUE_COMPLETE"

    // MARK: - Action Identifiers

    /// Action: reveal the output file in Finder.
    static let openFinderAction = "OPEN_FINDER"

    /// Action: start encoding the next queued job.
    static let encodeNextAction = "ENCODE_NEXT"

    /// Action: open the activity log to view error details.
    static let viewLogAction = "VIEW_LOG"

    /// Action: retry the failed encoding job.
    static let retryAction = "RETRY"

    /// Action: open the output folder in Finder.
    static let openOutputAction = "OPEN_OUTPUT"

    // MARK: - User Info Keys

    /// Key in `UNNotificationContent.userInfo` for the output file path.
    nonisolated static let outputPathKey = "outputPath"

    /// Key in `UNNotificationContent.userInfo` for the input file path (for retry).
    nonisolated static let inputPathKey = "inputPath"

    /// Key in `UNNotificationContent.userInfo` for the output directory path.
    nonisolated static let outputDirectoryKey = "outputDirectory"

    // MARK: - Category Registration

    /// Register notification categories and their associated actions with
    /// the system notification centre.
    ///
    /// Call this once at app launch, before any notifications are posted.
    /// Categories define which action buttons appear on each notification
    /// banner and in Notification Centre.
    func registerCategories() {
        // -- ENCODE_COMPLETE actions --
        let openFinderAction = UNNotificationAction(
            identifier: Self.openFinderAction,
            title: "Open in Finder",
            options: [.foreground]
        )
        let encodeNextAction = UNNotificationAction(
            identifier: Self.encodeNextAction,
            title: "Start Next",
            options: [.foreground]
        )
        let encodeCompleteCategory = UNNotificationCategory(
            identifier: Self.encodeCompleteCategory,
            actions: [openFinderAction, encodeNextAction],
            intentIdentifiers: [],
            options: []
        )

        // -- ENCODE_FAILED actions --
        let viewLogAction = UNNotificationAction(
            identifier: Self.viewLogAction,
            title: "View Log",
            options: [.foreground]
        )
        let retryAction = UNNotificationAction(
            identifier: Self.retryAction,
            title: "Retry",
            options: [.foreground]
        )
        let encodeFailedCategory = UNNotificationCategory(
            identifier: Self.encodeFailedCategory,
            actions: [viewLogAction, retryAction],
            intentIdentifiers: [],
            options: []
        )

        // -- QUEUE_COMPLETE actions --
        let openOutputAction = UNNotificationAction(
            identifier: Self.openOutputAction,
            title: "Open Output Folder",
            options: [.foreground]
        )
        let queueCompleteCategory = UNNotificationCategory(
            identifier: Self.queueCompleteCategory,
            actions: [openOutputAction],
            intentIdentifiers: [],
            options: []
        )

        // Register all categories
        UNUserNotificationCenter.current().setNotificationCategories([
            encodeCompleteCategory,
            encodeFailedCategory,
            queueCompleteCategory
        ])
    }

    // MARK: - Delegate — Action Handling

    /// Called when the user taps an action button on a notification banner.
    ///
    /// Routes each action identifier to the appropriate handler method.
    /// All actions bring the app to the foreground (`.foreground` option).
    ///
    /// - Parameters:
    ///   - center: The notification centre that received the response.
    ///   - response: The user's response, including the action identifier
    ///     and the original notification content with `userInfo`.
    ///   - completionHandler: Must be called when processing is complete.
    @preconcurrency nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Extract sendable values before crossing isolation boundaries.
        // `userInfo` is `[AnyHashable: Any]` (non-Sendable), so we pull
        // out only the String values we need on the nonisolated side.
        let actionIdentifier = response.actionIdentifier
        let outputPath = response.notification.request.content.userInfo[Self.outputPathKey] as? String
        let inputPath = response.notification.request.content.userInfo[Self.inputPathKey] as? String
        let outputDirectory = response.notification.request.content.userInfo[Self.outputDirectoryKey] as? String

        // Dispatch action handling to the main actor asynchronously.
        // completionHandler is called synchronously to satisfy the delegate
        // contract — the action handling continues in the background.
        Task { @MainActor in
            switch actionIdentifier {
            case Self.openFinderAction:
                handleOpenInFinder(outputPath: outputPath)

            case Self.encodeNextAction:
                handleEncodeNext()

            case Self.viewLogAction:
                handleViewLog()

            case Self.retryAction:
                handleRetry(inputPath: inputPath)

            case Self.openOutputAction:
                handleOpenOutputFolder(directoryPath: outputDirectory)

            case UNNotificationDefaultActionIdentifier:
                NSApp.activate(ignoringOtherApps: true)

            default:
                break
            }
        }

        // Call completion handler synchronously to avoid sending across actors.
        completionHandler()
    }

    /// Called when a notification is about to be presented while the app is
    /// in the foreground. Allows banners to appear even when the app is active.
    ///
    /// - Parameters:
    ///   - center: The notification centre.
    ///   - notification: The notification about to be delivered.
    ///   - completionHandler: Call with the desired presentation options.
    @preconcurrency nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even when the app is in the foreground
        completionHandler([.banner, .sound])
    }

    // MARK: - Action Handlers

    /// Reveal the completed output file in Finder.
    ///
    /// - Parameter outputPath: The output file path extracted from the
    ///   notification's `userInfo` dictionary, or `nil` if not present.
    private func handleOpenInFinder(outputPath: String?) {
        guard let outputPath else { return }
        let url = URL(fileURLWithPath: outputPath)
        NSWorkspace.shared.selectFile(
            url.path,
            inFileViewerRootedAtPath: url.deletingLastPathComponent().path
        )
    }

    /// Start encoding the next job in the queue.
    ///
    /// Posts a notification so that `AppViewModel` can pick up the request
    /// and call `startQueue()`. This avoids a direct dependency on the
    /// view model instance.
    private func handleEncodeNext() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .notificationActionEncodeNext,
            object: nil
        )
    }

    /// Switch to the activity log view to inspect error details.
    ///
    /// Posts a notification so that `AppViewModel` can set the navigation
    /// selection to `.log`.
    private func handleViewLog() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .notificationActionViewLog,
            object: nil
        )
    }

    /// Retry a failed encoding job.
    ///
    /// Posts a notification so that `AppViewModel` can re-import the file
    /// and re-enqueue it.
    ///
    /// - Parameter inputPath: The input file path extracted from the
    ///   notification's `userInfo` dictionary, or `nil` if not present.
    private func handleRetry(inputPath: String?) {
        NSApp.activate(ignoringOtherApps: true)

        guard let inputPath else { return }
        let url = URL(fileURLWithPath: inputPath)

        NotificationCenter.default.post(
            name: .notificationActionRetry,
            object: nil,
            userInfo: [Self.inputPathKey: url]
        )
    }

    /// Open the output folder in Finder.
    ///
    /// - Parameter directoryPath: The output directory path extracted from
    ///   the notification's `userInfo` dictionary, or `nil` if not present.
    private func handleOpenOutputFolder(directoryPath: String?) {
        guard let directoryPath else { return }
        let url = URL(fileURLWithPath: directoryPath)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Notification Action Names

extension Notification.Name {

    /// Posted when the user taps "Start Next" on an encode-complete notification.
    static let notificationActionEncodeNext = Notification.Name(
        "Ltd.MWBMpartners.MeedyaConverter.notificationActionEncodeNext"
    )

    /// Posted when the user taps "View Log" on an encode-failed notification.
    static let notificationActionViewLog = Notification.Name(
        "Ltd.MWBMpartners.MeedyaConverter.notificationActionViewLog"
    )

    /// Posted when the user taps "Retry" on an encode-failed notification.
    ///
    /// The `userInfo` dictionary contains:
    /// - ``NotificationActionHandler/inputPathKey``: `URL` — the source file to retry.
    static let notificationActionRetry = Notification.Name(
        "Ltd.MWBMpartners.MeedyaConverter.notificationActionRetry"
    )
}
