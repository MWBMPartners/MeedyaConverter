// ============================================================================
// MeedyaConverter — EDLEditorView (Issue #342)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - EDLEditorView
// ---------------------------------------------------------------------------
/// Edit Decision List editor for importing, editing, and exporting EDL
/// and FCPXML timeline data.
///
/// Supports:
/// - Importing CMX 3600 `.edl` files and Final Cut Pro `.fcpxml` files
/// - Editing event properties (reel name, timecodes, track type)
/// - Adding and removing events
/// - Converting chapter markers from the current media file to EDL events
/// - Exporting in CMX 3600 and FCPXML formats
///
/// Phase 14 — EDL and XML Roundtrip (Issue #342)
struct EDLEditorView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The list of EDL events currently being edited.
    @State private var events: [EDLEvent] = []

    /// The ID of the currently selected event for detail editing.
    @State private var selectedEventID: UUID?

    /// Title used when exporting EDL/FCPXML files.
    @State private var sequenceTitle: String = "Untitled Sequence"

    /// Controls visibility of the import file panel.
    @State private var showImportPanel = false

    /// Controls visibility of the export file panel.
    @State private var showExportPanel = false

    /// The export format chosen by the user.
    @State private var exportFormat: ExportFormat = .cmx3600

    /// Error message from the most recent operation, if any.
    @State private var errorMessage: String?

    // MARK: - Types

    /// Supported export formats for the EDL editor.
    private enum ExportFormat: String, CaseIterable {
        case cmx3600 = "CMX 3600 (.edl)"
        case fcpxml = "FCPXML (.fcpxml)"
    }

    // MARK: - Computed Properties

    /// The currently selected event, if any.
    private var selectedEvent: EDLEvent? {
        events.first { $0.id == selectedEventID }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Main content
            if events.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    eventListView
                        .frame(minWidth: 400)

                    eventDetailView
                        .frame(minWidth: 280)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }

    // MARK: - Toolbar

    /// Top toolbar with import/export and editing actions.
    private var toolbar: some View {
        HStack(spacing: 12) {
            // Import button
            Button {
                showImportPanel = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .fileImporter(
                isPresented: $showImportPanel,
                allowedContentTypes: [.plainText, .xml],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }

            // Convert from chapters
            Button {
                convertFromChapters()
            } label: {
                Label("From Chapters", systemImage: "list.number")
            }
            .disabled(viewModel.selectedFile == nil)

            Divider()
                .frame(height: 20)

            // Add event
            Button {
                addEvent()
            } label: {
                Label("Add Event", systemImage: "plus")
            }

            // Remove selected event
            Button {
                removeSelectedEvent()
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .disabled(selectedEventID == nil)

            Spacer()

            // Sequence title
            TextField("Sequence Title", text: $sequenceTitle)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            // Export format picker
            Picker("Format:", selection: $exportFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .frame(maxWidth: 180)

            // Export button
            Button {
                showExportPanel = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(events.isEmpty)
            .fileExporter(
                isPresented: $showExportPanel,
                document: EDLDocument(content: generateExport()),
                contentType: exportFormat == .cmx3600 ? .plainText : .xml,
                defaultFilename: exportFormat == .cmx3600
                    ? "\(sequenceTitle).edl"
                    : "\(sequenceTitle).fcpxml"
            ) { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Event List

    /// Table view of all EDL events.
    private var eventListView: some View {
        Table(events, selection: $selectedEventID) {
            TableColumn("#") { event in
                Text(String(format: "%03d", event.eventNumber))
                    .monospacedDigit()
            }
            .width(min: 40, ideal: 50, max: 60)

            TableColumn("Reel") { event in
                Text(event.reelName)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Track") { event in
                Text(event.trackType)
            }
            .width(min: 40, ideal: 50, max: 60)

            TableColumn("Edit") { event in
                Text(event.editType)
            }
            .width(min: 30, ideal: 40, max: 50)

            TableColumn("Source In") { event in
                Text(event.sourceIn)
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("Source Out") { event in
                Text(event.sourceOut)
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("Record In") { event in
                Text(event.recordIn)
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("Record Out") { event in
                Text(event.recordOut)
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)
        }
    }

    // MARK: - Event Detail

    /// Detail editor for the selected event.
    private var eventDetailView: some View {
        Group {
            if let eventIndex = events.firstIndex(where: { $0.id == selectedEventID }) {
                Form {
                    Section("Event \(events[eventIndex].eventNumber)") {
                        TextField("Reel Name", text: $events[eventIndex].reelName)

                        Picker("Track Type", selection: $events[eventIndex].trackType) {
                            Text("Video").tag("V")
                            Text("Audio 1").tag("A")
                            Text("Audio 2").tag("A2")
                            Text("Both").tag("B")
                        }

                        Picker("Edit Type", selection: $events[eventIndex].editType) {
                            Text("Cut").tag("C")
                            Text("Dissolve").tag("D")
                            Text("Wipe").tag("W")
                        }
                    }

                    Section("Source Timecodes") {
                        TextField("Source In", text: $events[eventIndex].sourceIn)
                            .monospacedDigit()
                        TextField("Source Out", text: $events[eventIndex].sourceOut)
                            .monospacedDigit()
                    }

                    Section("Record Timecodes") {
                        TextField("Record In", text: $events[eventIndex].recordIn)
                            .monospacedDigit()
                        TextField("Record Out", text: $events[eventIndex].recordOut)
                            .monospacedDigit()
                    }
                }
                .formStyle(.grouped)
                .padding()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)

                    Text("Select an event to edit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Empty State

    /// Placeholder shown when no events are loaded.
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("EDL Editor")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import an EDL or FCPXML file, or convert chapter markers to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Handles the result of the file import panel.
    private func handleImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let ext = url.pathExtension.lowercased()

                if ext == "fcpxml" || ext == "xml" {
                    events = EDLHandler.parseFCPXML(content)
                } else {
                    events = EDLHandler.parseCMX3600(content)
                }

                if events.isEmpty {
                    errorMessage = "No events found in the imported file."
                } else {
                    errorMessage = nil
                    sequenceTitle = url.deletingPathExtension().lastPathComponent
                }
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Converts chapter markers from the selected media file to EDL events.
    private func convertFromChapters() {
        guard let file = viewModel.selectedFile else {
            errorMessage = "No file selected."
            return
        }

        let chapters = file.chapters
        guard !chapters.isEmpty else {
            errorMessage = "No chapters found in the selected file."
            return
        }

        events = EDLHandler.eventsFromChapters(chapters: chapters)
        sequenceTitle = file.fileName
        errorMessage = nil
    }

    /// Adds a new blank event at the end of the list.
    private func addEvent() {
        let nextNumber = (events.map(\.eventNumber).max() ?? 0) + 1
        let newEvent = EDLEvent(
            eventNumber: nextNumber,
            reelName: "AX",
            trackType: "V",
            editType: "C",
            sourceIn: "00:00:00:00",
            sourceOut: "00:00:00:00",
            recordIn: "00:00:00:00",
            recordOut: "00:00:00:00"
        )
        events.append(newEvent)
        selectedEventID = newEvent.id
    }

    /// Removes the currently selected event.
    private func removeSelectedEvent() {
        guard let id = selectedEventID else { return }
        events.removeAll { $0.id == id }
        selectedEventID = events.first?.id
    }

    /// Generates the export string in the selected format.
    private func generateExport() -> String {
        switch exportFormat {
        case .cmx3600:
            return EDLHandler.generateCMX3600(events: events, title: sequenceTitle)
        case .fcpxml:
            return EDLHandler.generateFCPXML(events: events, title: sequenceTitle)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - EDLDocument
// ---------------------------------------------------------------------------
/// A `FileDocument` wrapper for exporting EDL/FCPXML content.
struct EDLDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.plainText, .xml] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(content.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
