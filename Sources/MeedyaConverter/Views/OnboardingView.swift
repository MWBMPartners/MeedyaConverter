// ============================================================================
// MeedyaConverter — OnboardingView (Issue #337)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// First-launch onboarding wizard that guides new users through initial
// setup. The wizard consists of five steps:
//
//   1. **Welcome** — app name, icon, and a "Get Started" button.
//   2. **FFmpeg Detection** — auto-detects FFmpeg, shows path, provides
//      manual browse and install instructions if not found.
//   3. **Default Profile** — pick a default encoding profile from the
//      built-in list with descriptions.
//   4. **Key Features** — highlights 4-5 key features with SF Symbol icons.
//   5. **Privacy & Analytics** — opt-in toggle with explanation of what
//      is collected and a link to the privacy policy.
//
// The wizard is shown only on first launch, controlled by the
// `hasCompletedOnboarding` AppStorage flag. Users can skip the wizard
// at any step.
//
// Phase 14 — First-Launch Onboarding Wizard (Issue #337)
// ---------------------------------------------------------------------------

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - OnboardingState
// ---------------------------------------------------------------------------
/// Observable state model for the onboarding wizard.
///
/// Tracks the current step, persists completion status, and holds
/// transient data collected during the wizard flow (FFmpeg path,
/// selected profile, analytics opt-in).
///
/// Marked `@MainActor` because all mutations are driven by SwiftUI
/// views on the main thread.
@MainActor
@Observable
final class OnboardingState {

    // MARK: - Navigation

    /// The zero-based index of the current wizard step.
    var currentStep: Int = 0

    /// The total number of steps in the wizard.
    let totalSteps: Int = 5

    // MARK: - Completion Persistence

    /// Whether the user has completed (or skipped) the onboarding wizard.
    ///
    /// Persisted to UserDefaults via `@AppStorage` in the view layer.
    /// This property is set to `true` when the user reaches the final
    /// step and taps "Get Started" or at any point taps "Skip".
    var hasCompletedOnboarding: Bool = false

    // MARK: - FFmpeg Detection (Step 2)

    /// The detected FFmpeg binary path, if found.
    var detectedFFmpegPath: String?

    /// Whether FFmpeg detection is currently in progress.
    var isDetectingFFmpeg: Bool = false

    /// Error message if FFmpeg detection failed.
    var ffmpegDetectionError: String?

    // MARK: - Default Profile (Step 3)

    /// The user's selected default encoding profile.
    var selectedDefaultProfile: EncodingProfile?

    // MARK: - Analytics (Step 5)

    /// Whether the user has opted in to anonymous analytics.
    var analyticsOptIn: Bool = false

    // MARK: - Navigation Methods

    /// Advance to the next step, clamped to the total.
    func nextStep() {
        if currentStep < totalSteps - 1 {
            currentStep += 1
        }
    }

    /// Go back to the previous step, clamped to zero.
    func previousStep() {
        if currentStep > 0 {
            currentStep -= 1
        }
    }

    /// Mark onboarding as complete.
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    /// Detect FFmpeg using the bundle manager's search paths.
    func detectFFmpeg() {
        isDetectingFFmpeg = true
        ffmpegDetectionError = nil
        detectedFFmpegPath = nil

        let manager = FFmpegBundleManager()
        do {
            let info = try manager.locateFFmpeg()
            detectedFFmpegPath = info.path
        } catch {
            ffmpegDetectionError = error.localizedDescription
        }

        isDetectingFFmpeg = false
    }
}

// ---------------------------------------------------------------------------
// MARK: - OnboardingView
// ---------------------------------------------------------------------------
/// A multi-step onboarding wizard presented as a modal sheet on first launch.
///
/// The view uses a `TabView` with `.page` style internally but renders
/// custom navigation controls (Back, Next, Skip, step indicator dots)
/// rather than relying on the system page indicators.
///
/// ### Architecture
/// - ``OnboardingState`` holds all mutable state.
/// - Each step is a separate private subview method for readability.
/// - The parent view checks `@AppStorage("hasCompletedOnboarding")` to
///   decide whether to present this sheet.
struct OnboardingView: View {

    // MARK: - State

    /// The onboarding state model, created locally since this view
    /// owns the wizard lifecycle.
    @State private var state = OnboardingState()

    /// Persisted flag controlling whether onboarding has been completed.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Dismiss action for the sheet presentation.
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Step content area.
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)

            Divider()

            // Navigation controls.
            navigationBar
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
        }
        .frame(width: 600, height: 480)
        .onAppear {
            state.detectFFmpeg()
        }
    }

    // MARK: - Step Content Router

    /// Routes to the correct step view based on the current step index.
    @ViewBuilder
    private var stepContent: some View {
        switch state.currentStep {
        case 0:
            welcomeStep
        case 1:
            ffmpegDetectionStep
        case 2:
            defaultProfileStep
        case 3:
            keyFeaturesStep
        case 4:
            privacyAnalyticsStep
        default:
            welcomeStep
        }
    }

    // MARK: - Step 1: Welcome

    /// Welcome screen with app name, icon, and introduction.
    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Welcome to MeedyaConverter")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("The professional media conversion toolkit for macOS. Convert, encode, and deliver your media with precision.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Text("Let's set up a few things to get you started.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Step 2: FFmpeg Detection

    /// FFmpeg detection step — auto-detects, shows path, and provides
    /// manual browse option.
    private var ffmpegDetectionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("FFmpeg Detection")
                .font(.title)
                .fontWeight(.bold)

            Text("MeedyaConverter requires FFmpeg for media encoding. We'll try to find it automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()

            // Detection result.
            if state.isDetectingFFmpeg {
                ProgressView("Searching for FFmpeg...")
            } else if let path = state.detectedFFmpegPath {
                VStack(spacing: 8) {
                    Label("FFmpeg found", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 12) {
                    Label("FFmpeg not found", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    if let error = state.ffmpegDetectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Install FFmpeg via Homebrew:")
                        .font(.callout)
                    Text("brew install ffmpeg")
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
                .padding()
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            // Manual browse button.
            HStack {
                Button("Browse for FFmpeg...") {
                    browseForFFmpeg()
                }
                .buttonStyle(.bordered)

                Button("Re-detect") {
                    state.detectFFmpeg()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Step 3: Default Profile

    /// Default encoding profile selection from built-in profiles.
    private var defaultProfileStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Choose a Default Profile")
                .font(.title)
                .fontWeight(.bold)

            Text("Select an encoding profile to use as your default. You can change this anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Profile list.
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(EncodingProfile.builtInProfiles.prefix(8)) { profile in
                        profileRow(profile)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 220)
        }
    }

    /// A single profile row in the default profile picker.
    ///
    /// - Parameter profile: The encoding profile to display.
    /// - Returns: A tappable row view with selection highlighting.
    private func profileRow(_ profile: EncodingProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.headline)
                Text(profile.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if state.selectedDefaultProfile?.id == profile.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(10)
        .background(
            state.selectedDefaultProfile?.id == profile.id
                ? Color.accentColor.opacity(0.1)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedDefaultProfile = profile
        }
    }

    // MARK: - Step 4: Key Features

    /// Key features showcase with SF Symbol icons.
    private var keyFeaturesStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Key Features")
                .font(.title)
                .fontWeight(.bold)

            Text("Here's what you can do with MeedyaConverter.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    icon: "film",
                    title: "Professional Encoding",
                    description: "H.264, H.265, ProRes, DNxHR, AV1, and more with hardware acceleration."
                )
                featureRow(
                    icon: "sun.max",
                    title: "HDR Support",
                    description: "HDR10, HLG, Dolby Vision tone-mapping and metadata preservation."
                )
                featureRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Streaming Output",
                    description: "Generate HLS and DASH manifests for adaptive bitrate streaming."
                )
                featureRow(
                    icon: "opticaldisc",
                    title: "Disc Authoring",
                    description: "Blu-ray and DVD compatible encoding with chapter support."
                )
                featureRow(
                    icon: "cloud.fill",
                    title: "Cloud Delivery",
                    description: "Upload encoded files to S3, GCS, or Backblaze B2 automatically."
                )
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    /// A single feature row with icon, title, and description.
    ///
    /// - Parameters:
    ///   - icon: The SF Symbol name for the feature icon.
    ///   - title: The feature title.
    ///   - description: A short description of the feature.
    /// - Returns: A horizontal layout with icon and text.
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 5: Privacy & Analytics

    /// Privacy and analytics opt-in step with toggle and explanation.
    private var privacyAnalyticsStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Privacy & Analytics")
                .font(.title)
                .fontWeight(.bold)

            Text("Your privacy matters. MeedyaConverter can collect anonymous usage data to help us improve the app.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()

            // Opt-in toggle.
            VStack(spacing: 16) {
                Toggle(isOn: $state.analyticsOptIn) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Share anonymous usage data")
                            .font(.headline)
                        Text("Help improve MeedyaConverter by sharing anonymised statistics.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                // What is collected.
                VStack(alignment: .leading, spacing: 8) {
                    Text("What we collect:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("Codecs and containers used (e.g., H.265, MKV)")
                        bulletPoint("Encode duration categories (short/medium/long)")
                        bulletPoint("Feature usage counts (no file names or content)")
                        bulletPoint("App version and macOS version")
                    }

                    Text("What we never collect:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("File names, paths, or media content")
                        bulletPoint("Personal information or account data")
                        bulletPoint("Network traffic or browsing history")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            }

            Spacer()

            // Privacy policy link.
            Link("View Privacy Policy", destination: URL(string: "https://mwbmpartners.com/privacy")!)
                .font(.caption)
        }
    }

    /// A single bullet point text line.
    ///
    /// - Parameter text: The text to display after the bullet.
    /// - Returns: An HStack with a bullet character and the text.
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
            Text(text)
        }
    }

    // MARK: - Navigation Bar

    /// Bottom navigation bar with Back, Next/Finish, Skip, and step dots.
    private var navigationBar: some View {
        HStack {
            // Skip button.
            Button("Skip") {
                hasCompletedOnboarding = true
                state.completeOnboarding()
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            // Step indicator dots.
            HStack(spacing: 8) {
                ForEach(0..<state.totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index == state.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Step \(index + 1) of \(state.totalSteps)")
                }
            }

            Spacer()

            // Back / Next buttons.
            HStack(spacing: 12) {
                if state.currentStep > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            state.previousStep()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if state.currentStep < state.totalSteps - 1 {
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            state.nextStep()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        hasCompletedOnboarding = true
                        state.completeOnboarding()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - File Picker

    /// Opens a file picker to manually browse for the FFmpeg binary.
    private func browseForFFmpeg() {
        let panel = NSOpenPanel()
        panel.title = "Locate FFmpeg Binary"
        panel.message = "Select the FFmpeg executable."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.detectedFFmpegPath = url.path
    }
}
