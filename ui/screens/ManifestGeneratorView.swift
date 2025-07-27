// File: adaptix/ui/screens/ManifestGeneratorView.swift
// Purpose: SwiftUI view for generating adaptive streaming manifests (HLS & MPEG-DASH)
// Role: Primary interface for users to configure, preview, and generate adaptive manifest files
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services)
// Version: 1.1.0

import SwiftUI

/// View for generating adaptive streaming manifests.
struct ManifestGeneratorView: View {
    @StateObject private var viewModel = EncodingManifestViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Form {
                Section(header: Text("🎞️ Source & Output")) {
                    TextField("Input Path", text: $viewModel.inputPath)
                    TextField("Output Directory", text: $viewModel.outputDirectory)
                }

                Section(header: Text("🎚️ Track Configuration")) {
                    ForEach($viewModel.trackGroups.indices, id: \._self) { index in
                        VStack(alignment: .leading) {
                            Text("Group \(index + 1)").font(.headline)

                            TextField("Group ID", text: $viewModel.trackGroups[index].groupID)
                            TextField("Language Code (e.g. en, fr)", text: $viewModel.trackGroups[index].languageCode)
                            TextField("Language Label (auto fills native name if blank)", text: $viewModel.trackGroups[index].label)

                            Toggle("Default Track", isOn: $viewModel.trackGroups[index].isDefault)
                            Toggle("Forced Track", isOn: $viewModel.trackGroups[index].isForced)

                            Divider()
                        }
                    }

                    Button("➕ Add Track Group") {
                        viewModel.trackGroups.append(TrackGroup(groupID: "", languageCode: "", label: "", isDefault: false, isForced: false))
                    }
                }

                Section(header: Text("🔐 Encryption Settings")) {
                    Toggle("Enable Encryption", isOn: $viewModel.enableEncryption)
                    if viewModel.enableEncryption {
                        TextField("Encryption Key (hex)", text: $viewModel.encryptionKey)
                        TextField("Key URL", text: $viewModel.encryptionKeyURL)
                    }
                }

                Section(header: Text("⚙️ Generation Controls")) {
                    Button("🚀 Generate Manifest") {
                        viewModel.generateManifest()
                    }
                    .disabled(!viewModel.canGenerate)

                    if !viewModel.generationProgress.isEmpty {
                        ProgressView(viewModel.generationProgress)
                    }
                }

                Section(header: Text("📄 Output Tabs")) {
                    Picker("View", selection: $viewModel.selectedTab) {
                        Text("Logs").tag("Logs")
                        Text("Previews").tag("Previews")
                        Text("Manifest Summary").tag("Summary")
                    }.pickerStyle(SegmentedPickerStyle())

                    if viewModel.selectedTab == "Logs" {
                        ScrollView {
                            Text(viewModel.logMessages.joined(separator: "\n"))
                                .font(.system(.footnote, design: .monospaced))
                                .padding()
                        }
                    } else if viewModel.selectedTab == "Previews" {
                        ScrollView {
                            ForEach(viewModel.generatedPreviews, id: \._self) { preview in
                                Text(preview)
                                    .font(.footnote)
                                    .padding(.bottom, 2)
                            }
                        }
                    } else {
                        ScrollView {
                            Text(viewModel.generatedManifestSummary)
                                .font(.footnote)
                                .padding()
                        }
                    }
                }
            }
        }
        .padding()
        .onChange(of: viewModel.trackGroups) { _ in
            viewModel.updateLanguageLabelsIfNeeded()
        }
    }
}