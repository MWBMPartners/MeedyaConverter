// ============================================================================
// MeedyaConverter — ImageConversionView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import ConverterEngine

// MARK: - ImageConversionView

/// The image conversion interface providing file import, thumbnail grid,
/// image preview, conversion settings, and batch processing controls.
///
/// Uses a three-column layout: sidebar (input files), grid (thumbnails),
/// and detail (preview + settings).
///
/// Phase 17 — Image Conversion UI (Issue #229)
struct ImageConversionView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var imageFiles: [ImageFileItem] = []
    @State private var selectedImages: Set<UUID> = []
    @State private var thumbnailSize: ThumbnailSize = .medium
    @State private var sortOrder: ImageSortOrder = .name
    @State private var filterFormat: ImageFormat? = nil

    // Conversion settings
    @State private var outputFormat: ImageFormat = .jpeg
    @State private var quality: ImageQuality = .high
    @State private var resizeWidth: Int?
    @State private var resizeHeight: Int?
    @State private var resizeMode: ImageResizeMode = .fit
    @State private var stripMetadata: Bool = false
    @State private var autoRotate: Bool = true
    @State private var outputDirectory: URL?

    // Processing state
    @State private var isConverting: Bool = false
    @State private var conversionProgress: Double = 0
    @State private var completedCount: Int = 0
    @State private var failedCount: Int = 0
    @State private var conversionErrors: [String] = []

    // Preview
    @State private var previewImage: ImageFileItem?

    // Thumbnail cache
    @State private var thumbnailCache = ThumbnailCache()

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            imageSidebar
        } content: {
            thumbnailGrid
        } detail: {
            detailPanel
        }
        .navigationTitle("Image Conversion")
        .toolbar { imageToolbar }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: - Sidebar (Input Files)

    private var imageSidebar: some View {
        List(selection: $selectedImages) {
            Section("Input Images (\(imageFiles.count))") {
                ForEach(sortedFilteredImages) { item in
                    imageListRow(item)
                }
                .onDelete { indexSet in
                    let sorted = sortedFilteredImages
                    for index in indexSet {
                        if let fileIndex = imageFiles.firstIndex(where: { $0.id == sorted[index].id }) {
                            imageFiles.remove(at: fileIndex)
                        }
                    }
                }
            }

            Section("Conversion Queue") {
                if isConverting {
                    ProgressView(value: conversionProgress) {
                        Text("\(completedCount)/\(imagesToConvert.count) converted")
                    }
                    .accessibilityLabel("Conversion progress")
                    .accessibilityValue("\(completedCount) of \(imagesToConvert.count) images converted")
                }

                if !conversionErrors.isEmpty {
                    DisclosureGroup("Errors (\(conversionErrors.count))") {
                        ForEach(conversionErrors, id: \.self) { error in
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("History") {
                if completedCount > 0 {
                    Text("\(completedCount) converted, \(failedCount) failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No conversions yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
    }

    private func imageListRow(_ item: ImageFileItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(item.formatDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(item.id)
    }

    // MARK: - Thumbnail Grid

    private var thumbnailGrid: some View {
        VStack(spacing: 0) {
            // Grid toolbar
            HStack {
                Picker("Size", selection: $thumbnailSize) {
                    ForEach(ThumbnailSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                Picker("Sort", selection: $sortOrder) {
                    ForEach(ImageSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .frame(maxWidth: 140)

                Picker("Format", selection: $filterFormat) {
                    Text("All Formats").tag(nil as ImageFormat?)
                    ForEach(ImageFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format as ImageFormat?)
                    }
                }
                .frame(maxWidth: 140)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if imageFiles.isEmpty {
                ContentUnavailableView {
                    Label("No Images", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Drag and drop images or click Import to add files.")
                } actions: {
                    Button("Import Images") { importImages() }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: thumbnailSize.spacing) {
                        ForEach(sortedFilteredImages) { item in
                            thumbnailCell(item)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func thumbnailCell(_ item: ImageFileItem) -> some View {
        let isSelected = selectedImages.contains(item.id)

        return VStack(spacing: 4) {
            // Thumbnail — served from cache or loaded asynchronously
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)

                if let cached = thumbnailCache.thumbnail(for: item.url, size: thumbnailSize.cellSize) {
                    Image(nsImage: cached)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )
            .task(id: item.url) {
                _ = await thumbnailCache.loadThumbnail(for: item.url, size: thumbnailSize.cellSize)
            }

            Text(item.fileName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(item.dimensionsString)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: thumbnailSize.cellSize, height: thumbnailSize.cellSize + 30)
        .onTapGesture {
            if selectedImages.contains(item.id) {
                selectedImages.remove(item.id)
            } else {
                selectedImages.insert(item.id)
            }
            previewImage = item
        }
        .accessibilityLabel("\(item.fileName), \(item.formatDescription)")
    }

    // MARK: - Detail Panel (Preview + Settings)

    private var detailPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Preview
                if let preview = previewImage {
                    imagePreview(preview)
                }

                Divider()

                // Conversion settings
                conversionSettingsPanel

                Divider()

                // Batch controls
                batchControls
            }
            .padding()
        }
    }

    /// Maximum pixel dimension used for the detail preview thumbnail.
    private static let previewThumbnailSize: CGFloat = 600

    @ViewBuilder
    private func imagePreview(_ item: ImageFileItem) -> some View {
        VStack(spacing: 8) {
            if let cached = thumbnailCache.thumbnail(for: item.url, size: Self.previewThumbnailSize) {
                Image(nsImage: cached)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Preview of \(item.fileName)")
            } else {
                ProgressView("Loading preview…")
                    .frame(height: 200)
                    .task(id: item.url) {
                        _ = await thumbnailCache.loadThumbnail(for: item.url, size: Self.previewThumbnailSize)
                    }
            }

            // Metadata overlay
            HStack(spacing: 16) {
                Label(item.fileName, systemImage: "doc")
                    .font(.caption)
                Label(item.dimensionsString, systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                Label(item.fileSizeString, systemImage: "internaldrive")
                    .font(.caption)
                Label(item.formatDescription, systemImage: "photo")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.fileName), \(item.dimensionsString), \(item.fileSizeString), \(item.formatDescription)")
        }
    }

    // MARK: - Conversion Settings Panel

    private var conversionSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion Settings")
                .font(.headline)

            // Output format
            Picker("Output Format", selection: $outputFormat) {
                ForEach(ImageFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .accessibilityLabel("Output image format")

            // Format info
            HStack(spacing: 12) {
                if outputFormat.supportsAlpha {
                    Label("Alpha", systemImage: "checkerboard.rectangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if outputFormat.supportsHDR {
                    Label("HDR", systemImage: "sun.max")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
                if outputFormat.supportsLossless {
                    Label("Lossless", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Format capabilities: \(outputFormat.supportsAlpha ? "Alpha, " : "")\(outputFormat.supportsHDR ? "HDR, " : "")\(outputFormat.supportsLossless ? "Lossless" : "")")

            // Quality
            if !quality.lossless {
                HStack {
                    Text("Quality: \(quality.quality)")
                    Slider(value: Binding(
                        get: { Double(quality.quality) },
                        set: { quality = ImageQuality(quality: Int($0), effort: quality.effort, lossless: quality.lossless) }
                    ), in: 1...100)
                    .accessibilityLabel("Image quality")
                    .accessibilityValue("\(quality.quality) percent")
                }
            }

            if outputFormat.supportsLossless {
                Toggle("Lossless", isOn: Binding(
                    get: { quality.lossless },
                    set: { quality = ImageQuality(quality: quality.quality, effort: quality.effort, lossless: $0) }
                ))
            }

            Divider()

            // Resize
            Text("Resize")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                TextField("Width", value: $resizeWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
                    .accessibilityLabel("Resize width in pixels")
                Text("x")
                    .accessibilityHidden(true)
                TextField("Height", value: $resizeHeight, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
                    .accessibilityLabel("Resize height in pixels")

                Picker("Mode", selection: $resizeMode) {
                    Text("Fit").tag(ImageResizeMode.fit)
                    Text("Fill").tag(ImageResizeMode.fill)
                    Text("Exact").tag(ImageResizeMode.exact)
                    Text("Downscale").tag(ImageResizeMode.downscaleOnly)
                }
                .frame(maxWidth: 120)
                .accessibilityLabel("Resize mode")
            }

            Divider()

            // Metadata
            Text("Options")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle("Strip metadata (EXIF, XMP)", isOn: $stripMetadata)
                .accessibilityLabel("Remove image metadata from output")

            Toggle("Auto-rotate from EXIF", isOn: $autoRotate)
                .accessibilityLabel("Apply EXIF orientation before saving")

            Divider()

            // Output directory
            HStack {
                LabeledContent("Output") {
                    Text(outputDirectory?.lastPathComponent ?? "Same as source")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Choose...") { chooseOutputDirectory() }
            }
        }
    }

    // MARK: - Batch Controls

    private var batchControls: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    startConversion(all: true)
                } label: {
                    Label("Convert All (\(imageFiles.count))", systemImage: "photo.stack")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(imageFiles.isEmpty || isConverting)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Convert all imported images")

                Button {
                    startConversion(all: false)
                } label: {
                    Label("Convert Selected (\(selectedImages.count))", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(selectedImages.isEmpty || isConverting)
                .accessibilityLabel("Convert selected images")
            }

            if isConverting {
                HStack {
                    ProgressView(value: conversionProgress) {
                        Text("Converting \(completedCount + failedCount)/\(imagesToConvert.count)...")
                    }
                    .accessibilityLabel("Batch conversion progress")
                    .accessibilityValue("\(completedCount + failedCount) of \(imagesToConvert.count) processed")

                    Button("Cancel") {
                        isConverting = false
                    }
                    .accessibilityLabel("Cancel image conversion")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var imageToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                importImages()
            } label: {
                Label("Import", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .help("Import images (Cmd+O)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                imageFiles.removeAll()
                selectedImages.removeAll()
                previewImage = nil
                thumbnailCache.clearCache()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(imageFiles.isEmpty)
            .help("Remove all images")
        }
    }

    // MARK: - Grid Configuration

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize.cellSize, maximum: thumbnailSize.cellSize + 20))]
    }

    private var sortedFilteredImages: [ImageFileItem] {
        var items = imageFiles

        // Filter
        if let format = filterFormat {
            items = items.filter { $0.format == format }
        }

        // Sort
        switch sortOrder {
        case .name:
            items.sort { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
        case .date:
            items.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .size:
            items.sort { $0.fileSize > $1.fileSize }
        case .format:
            items.sort { $0.format?.rawValue ?? "" < $1.format?.rawValue ?? "" }
        }

        return items
    }

    private var imagesToConvert: [ImageFileItem] {
        return imageFiles
    }

    // MARK: - Actions

    private func importImages() {
        let panel = NSOpenPanel()
        panel.title = "Import Images"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .webP, .gif, .bmp]

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            addImageFile(url)
        }

        // Preload thumbnails for the newly imported images
        thumbnailCache.preload(urls: imageFiles.map(\.url), size: thumbnailSize.cellSize)
    }

    private func addImageFile(_ url: URL) {
        // Handle directories
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                if ImageConverter.isImageFile(fileURL.lastPathComponent) {
                    addSingleImage(fileURL)
                }
            }
        } else if ImageConverter.isImageFile(url.lastPathComponent) {
            addSingleImage(url)
        }
    }

    private func addSingleImage(_ url: URL) {
        guard !imageFiles.contains(where: { $0.url == url }) else { return }

        let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let format = ImageFormat.from(extension: url.pathExtension)

        // Get image dimensions
        var width: Int = 0
        var height: Int = 0
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
            width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
            height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        }

        let item = ImageFileItem(
            url: url,
            format: format,
            fileSize: Int64(resources?.fileSize ?? 0),
            modificationDate: resources?.contentModificationDate,
            width: width,
            height: height
        )

        imageFiles.append(item)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    addImageFile(url)
                }
            }
        }
    }

    private func startConversion(all: Bool) {
        let filesToConvert = all ? imageFiles : imageFiles.filter { selectedImages.contains($0.id) }
        guard !filesToConvert.isEmpty else { return }

        isConverting = true
        completedCount = 0
        failedCount = 0
        conversionErrors = []
        conversionProgress = 0

        let config = ImageConvertConfig(
            outputFormat: outputFormat,
            quality: quality,
            width: resizeWidth,
            height: resizeHeight,
            resizeMode: resizeMode,
            stripMetadata: stripMetadata,
            autoRotate: autoRotate
        )

        Task.detached { [filesToConvert, outputDirectory, outputFormat, config] in
            for (index, file) in filesToConvert.enumerated() {
                guard await MainActor.run(body: { isConverting }) else { break }

                let outputDir = outputDirectory ?? file.url.deletingLastPathComponent()
                let baseName = file.url.deletingPathExtension().lastPathComponent
                let outputPath = outputDir
                    .appendingPathComponent(baseName)
                    .appendingPathExtension(outputFormat.fileExtension)
                    .path

                let args = ImageConverter.buildConvertArguments(
                    inputPath: file.url.path,
                    outputPath: outputPath,
                    config: config
                )

                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["ffmpeg"] + args

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        await MainActor.run {
                            completedCount += 1
                        }
                    } else {
                        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        await MainActor.run {
                            failedCount += 1
                            conversionErrors.append("\(file.fileName): \(errorStr)")
                        }
                    }
                } catch {
                    await MainActor.run {
                        failedCount += 1
                        conversionErrors.append("\(file.fileName): \(error.localizedDescription)")
                    }
                }

                await MainActor.run {
                    conversionProgress = Double(index + 1) / Double(filesToConvert.count)
                }
            }

            await MainActor.run {
                isConverting = false
                viewModel.appendLog(.info,
                    "Image conversion complete: \(completedCount) succeeded, \(failedCount) failed")
            }
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectory = url
    }
}

// MARK: - ImageFileItem

/// Represents a single image file in the conversion interface.
struct ImageFileItem: Identifiable {
    let id = UUID()
    let url: URL
    let format: ImageFormat?
    let fileSize: Int64
    let modificationDate: Date?
    let width: Int
    let height: Int

    var fileName: String { url.lastPathComponent }

    var formatDescription: String {
        format?.displayName ?? url.pathExtension.uppercased()
    }

    var dimensionsString: String {
        guard width > 0, height > 0 else { return "Unknown" }
        return "\(width) x \(height)"
    }

    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - ThumbnailSize

/// Thumbnail display sizes for the image grid.
enum ThumbnailSize: String, CaseIterable {
    case small = "S"
    case medium = "M"
    case large = "L"

    var cellSize: CGFloat {
        switch self {
        case .small: return 80
        case .medium: return 120
        case .large: return 180
        }
    }

    var spacing: CGFloat {
        switch self {
        case .small: return 4
        case .medium: return 8
        case .large: return 12
        }
    }
}

// MARK: - ImageSortOrder

/// Sort options for the image grid.
enum ImageSortOrder: String, CaseIterable {
    case name = "Name"
    case date = "Date"
    case size = "Size"
    case format = "Format"
}
