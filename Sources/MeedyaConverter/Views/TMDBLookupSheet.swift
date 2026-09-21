// ============================================================================
// MeedyaConverter — TMDBLookupSheet (Issue #205)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Look a film up on TMDB and apply it to the metadata tag table — the video
// counterpart of `MusicBrainzLookupSheet`, and the first thing in the app
// that actually uses a keyed metadata provider (#205).
//
// NEVER A DEAD END. With no API key stored this does not present a Search
// button that can only fail: it says what is missing and offers the way to
// fix it, the same contract the gated MakeMKV screen follows.
//
// The API key is read once, when the sheet is built, and lives only inside
// the `TMDBLookupService` it constructs. It is never shown, never stored in
// view state of its own, and never reaches an error message — see
// `TMDBLookupService`'s redaction.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - TMDBLookupSheet

struct TMDBLookupSheet: View {

    let onApply: @MainActor (MetadataResult, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    @State private var title: String
    @State private var yearText: String
    @State private var results: [MetadataResult] = []
    @State private var selectedID: String?
    @State private var isSearching = false
    @State private var statusMessage: String?
    @State private var includeIdentifiers = true
    @State private var searchTask: Task<Void, Never>?

    /// `nil` when no TMDB key is stored. Kept as an optional rather than an
    /// empty-keyed service so the "set a key up" state is a fact about the
    /// sheet rather than something inferred from a failed search.
    private let service: TMDBLookupService?

    init(
        initialTitle: String,
        initialYear: Int?,
        onApply: @escaping @MainActor (MetadataResult, Bool) -> Void
    ) {
        _title = State(initialValue: initialTitle)
        _yearText = State(initialValue: initialYear.map { String($0) } ?? "")
        self.onApply = onApply

        // Read once, here. The key never becomes view state.
        let stored = APIKeyManager().key(for: .tmdb)?.apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            self.service = TMDBLookupService(apiKey: stored)
        } else {
            self.service = nil
        }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Look up a film on TMDB")
                .font(.headline)

            if service == nil {
                missingKeyView
            } else {
                searchForm
                resultsList
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusMessage.hasPrefix("Error") ? .red : .secondary)
                }
                Toggle("Include the TMDB id as a tag", isOn: $includeIdentifiers)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 440)
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: No key yet

    @ViewBuilder
    private var missingKeyView: some View {
        ContentUnavailableView {
            Label("No TMDB key yet", systemImage: "key")
        } description: {
            Text(
                "Looking films up needs a free key from themoviedb.org. "
                + "Add one under Settings \u{203A} Metadata, then try again."
            )
        } actions: {
            Button("Open Settings\u{2026}") { openSettings() }
                .buttonStyle(.borderedProminent)
            Link("Get a key\u{2026}", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
        }
    }

    // MARK: Search

    @ViewBuilder
    private var searchForm: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Year", text: $yearText, prompt: Text("Any year"))
        }
        .formStyle(.grouped)
        .frame(maxHeight: 120)

        HStack {
            Button("Search") { search() }
                .disabled(isSearching || title.trimmingCharacters(in: .whitespaces).isEmpty)
            if isSearching {
                ProgressView().controlSize(.small)
                Button("Cancel", role: .cancel) { searchTask?.cancel() }
            }
            Spacer()
        }

        if !isSearching, title.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Enter a title to search for.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        // `MetadataResult` is not `Identifiable`, so the id keypath is
        // explicit. TMDB ids are unique within a result set.
        List(selection: $selectedID) {
            ForEach(results, id: \.externalId) { result in
                resultRow(for: result).tag(result.externalId)
            }
        }
        .frame(minHeight: 200)
    }

    private func resultRow(for result: MetadataResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.year.map { "\(result.title) (\($0))" } ?? result.title)
            if let runtime = result.runtimeMinutes {
                Text("\(runtime) minutes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let overview = result.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Apply") {
                guard let chosen = results.first(where: { $0.externalId == selectedID }) else { return }
                onApply(chosen, includeIdentifiers)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedID == nil)
        }
    }

    // MARK: Searching

    private func search() {
        guard !isSearching, let service else { return }
        let queryTitle = title
        // A year the user cannot have meant is ignored rather than sent —
        // a wrong year filter hides the right film completely.
        let year = Int(yearText.trimmingCharacters(in: .whitespaces))
            .flatMap { (1900...2100).contains($0) ? $0 : nil }

        isSearching = true
        statusMessage = nil
        results = []
        selectedID = nil

        searchTask = Task {
            // `defer`, not a line at the end: the cancellation guard below
            // returns EARLY, and without this the spinner would keep
            // spinning with Search disabled and Cancel doing nothing,
            // recoverable only by closing the sheet.
            defer { isSearching = false }
            do {
                let found = try await service.searchMovies(title: queryTitle, year: year)
                // Running times come only from the details endpoint, and they
                // are what make two same-named films tellable apart.
                let enriched = try await service.withRuntimes(found)
                guard !Task.isCancelled else { return }
                results = enriched
                selectedID = enriched.first?.externalId
                statusMessage = enriched.isEmpty
                    ? "TMDB found nothing under that title."
                    : "\(enriched.count) result\(enriched.count == 1 ? "" : "s")."
            } catch is CancellationError {
                statusMessage = "Cancelled."
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
}
