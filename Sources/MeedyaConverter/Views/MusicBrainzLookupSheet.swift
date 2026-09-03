// ============================================================================
// MeedyaConverter — MusicBrainzLookupSheet (Issue #205, follows #493)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - MusicBrainzLookupSheet

/// Modal sheet that searches MusicBrainz recordings by title/artist and lets
/// the user pick a match to apply to the tag table. Presented from
/// `MetadataTagEditorView`'s "Look Up…" button.
struct MusicBrainzLookupSheet: View {
    let preferredAlbum: String?
    let fileDurationSeconds: Double?
    let onApply: @MainActor (MusicBrainzRecordingMatch, MusicBrainzRecordingMatch.Release?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var artist: String
    @State private var matches: [MusicBrainzRecordingMatch] = []
    @State private var selectedMatchID: String?
    @State private var isSearching = false
    @State private var statusMessage: String?
    @State private var includeIdentifiers = true
    @State private var searchTask: Task<Void, Never>?

    private let service = MusicBrainzLookupService()

    init(
        initialTitle: String,
        initialArtist: String,
        preferredAlbum: String?,
        fileDurationSeconds: Double?,
        onApply: @escaping @MainActor (MusicBrainzRecordingMatch, MusicBrainzRecordingMatch.Release?, Bool) -> Void
    ) {
        _title = State(initialValue: initialTitle)
        _artist = State(initialValue: initialArtist)
        self.preferredAlbum = preferredAlbum
        self.fileDurationSeconds = fileDurationSeconds
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Look Up on MusicBrainz")
                .font(.headline)

            Form {
                TextField("Title", text: $title)
                TextField("Artist", text: $artist)
            }

            HStack {
                Button("Search", action: search)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSearching || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel") { searchTask?.cancel() }
                }

                Spacer()
            }

            List(selection: $selectedMatchID) {
                ForEach(matches) { match in
                    matchRow(for: match)
                        .tag(match.id)
                }
            }
            .frame(minHeight: 200)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusMessage.hasPrefix("Error") ? .red : .secondary)
            }

            Toggle("Include MusicBrainz IDs as tags", isOn: $includeIdentifiers)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Apply") {
                    guard let match = matches.first(where: { $0.id == selectedMatchID }) else { return }
                    onApply(match, match.bestRelease(preferringAlbumTitled: preferredAlbum), includeIdentifiers)
                    dismiss()
                }
                .disabled(selectedMatchID == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 440)
        .onDisappear {
            searchTask?.cancel()
        }
    }

    /// One row in the results list: title/artist, then a caption joining
    /// the best release's title/date (or the recording's own first-release
    /// date), the recording length, its disambiguation, and its score.
    @ViewBuilder
    private func matchRow(for match: MusicBrainzRecordingMatch) -> some View {
        let bestRelease = match.bestRelease(preferringAlbumTitled: preferredAlbum)
        VStack(alignment: .leading, spacing: 2) {
            Text("\(match.title) — \(match.artist.isEmpty ? "Unknown artist" : match.artist)")
            Text(captionText(for: match, bestRelease: bestRelease))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func captionText(for match: MusicBrainzRecordingMatch, bestRelease: MusicBrainzRecordingMatch.Release?) -> String {
        var parts: [String] = []
        if let albumTitle = bestRelease?.title { parts.append(albumTitle) }
        if let date = bestRelease?.date ?? match.firstReleaseDate { parts.append(date) }
        if let lengthSeconds = match.lengthSeconds {
            let totalSeconds = Int(lengthSeconds.rounded())
            parts.append(String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60))
        }
        if let disambiguation = match.disambiguation, !disambiguation.isEmpty {
            parts.append(disambiguation)
        }
        parts.append("score \(match.score)")
        return parts.joined(separator: " · ")
    }

    private func search() {
        guard !isSearching else { return }
        let queryTitle = title
        let queryArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true
        statusMessage = nil
        matches = []
        selectedMatchID = nil
        searchTask = Task {
            do {
                let found = try await service.searchRecordings(
                    title: queryTitle,
                    artist: queryArtist.isEmpty ? nil : queryArtist
                )
                guard !Task.isCancelled else { return }
                matches = MusicBrainzTagMapping.ranked(found, fileDurationSeconds: fileDurationSeconds)
                selectedMatchID = matches.first?.id
                statusMessage = matches.isEmpty
                    ? "No MusicBrainz recordings matched."
                    : "\(matches.count) match\(matches.count == 1 ? "" : "es")."
            } catch is CancellationError {
                statusMessage = "Cancelled."
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
            isSearching = false
        }
    }
}
