// ============================================================================
// MeedyaConverter — FilterGraphEditorView (Issue #354)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers

// ---------------------------------------------------------------------------
// MARK: - FilterNodeType
// ---------------------------------------------------------------------------
/// Built-in FFmpeg filter node types available in the visual editor palette.
///
/// Each case represents a commonly used FFmpeg video or audio filter,
/// with pre-configured input/output counts and default parameters.
enum FilterNodeType: String, CaseIterable, Identifiable, Sendable {

    // MARK: - Video Filters

    /// Scale (resize) video to a target resolution.
    case scale

    /// Crop video to a specified rectangle.
    case crop

    /// Overlay one video stream on top of another.
    case overlay

    /// Tone-map HDR content to SDR using the Hable/Reinhard algorithm.
    case tonemap

    /// Apply a colour-space conversion (e.g., BT.709 to BT.2020).
    case colorspace

    /// Sharpen video using the unsharp mask filter.
    case unsharp

    /// Deinterlace video using the yadif algorithm.
    case yadif

    /// Apply a colour/gamma LUT for creative grading.
    case lut3d

    /// Draw text (timecode, watermark) on the video.
    case drawtext

    /// Adjust brightness, contrast, saturation, and gamma.
    case eq

    // MARK: - Audio Filters

    /// EBU R128 loudness normalisation.
    case loudnorm

    /// High-pass filter to remove low-frequency noise.
    case highpass

    /// Low-pass filter to remove high-frequency noise.
    case lowpass

    /// Audio compressor/limiter for dynamic range control.
    case compressor = "acompressor"

    /// Audio fade in/out.
    case afade

    // MARK: - Properties

    var id: String { rawValue }

    /// Human-readable display name for the palette.
    var displayName: String {
        switch self {
        case .scale:      return "Scale"
        case .crop:       return "Crop"
        case .overlay:    return "Overlay"
        case .tonemap:    return "Tonemap"
        case .colorspace: return "Colorspace"
        case .unsharp:    return "Unsharp"
        case .yadif:      return "Yadif"
        case .lut3d:      return "LUT 3D"
        case .drawtext:   return "Draw Text"
        case .eq:         return "EQ"
        case .loudnorm:   return "Loudnorm"
        case .highpass:   return "Highpass"
        case .lowpass:    return "Lowpass"
        case .compressor: return "Compressor"
        case .afade:      return "Audio Fade"
        }
    }

    /// Whether this is an audio filter (vs. video).
    var isAudioFilter: Bool {
        switch self {
        case .loudnorm, .highpass, .lowpass, .compressor, .afade:
            return true
        default:
            return false
        }
    }

    /// Number of inputs this filter accepts.
    var inputCount: Int {
        switch self {
        case .overlay: return 2
        default:       return 1
        }
    }

    /// Number of outputs this filter produces.
    var outputCount: Int { 1 }

    /// Default parameter key-value pairs for a new instance.
    var defaultParameters: [String: String] {
        switch self {
        case .scale:      return ["w": "1920", "h": "1080", "flags": "lanczos"]
        case .crop:       return ["w": "1920", "h": "1080", "x": "0", "y": "0"]
        case .overlay:    return ["x": "0", "y": "0"]
        case .tonemap:    return ["tonemap": "hable", "peak": "100"]
        case .colorspace: return ["all": "bt709"]
        case .unsharp:    return ["luma_msize_x": "5", "luma_msize_y": "5", "luma_amount": "1.0"]
        case .yadif:      return ["mode": "send_frame", "parity": "auto"]
        case .lut3d:      return ["file": ""]
        case .drawtext:   return ["text": "MeedyaConverter", "fontsize": "24", "fontcolor": "white"]
        case .eq:         return ["brightness": "0", "contrast": "1", "saturation": "1"]
        case .loudnorm:   return ["I": "-14", "LRA": "11", "TP": "-1.5"]
        case .highpass:   return ["f": "200"]
        case .lowpass:    return ["f": "3000"]
        case .compressor: return ["threshold": "0.089", "ratio": "4", "attack": "200", "release": "1000"]
        case .afade:      return ["t": "in", "d": "2"]
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - FilterNode
// ---------------------------------------------------------------------------
/// A single node in the visual filter graph, representing one FFmpeg filter.
///
/// Each node has a position on the canvas, a filter name, user-editable
/// parameters, and a defined number of inputs and outputs for connection.
struct FilterNode: Identifiable, Equatable, Sendable {

    /// Unique identifier for this node.
    let id: UUID

    /// The FFmpeg filter name (e.g., "scale", "loudnorm").
    var filterName: String

    /// User-editable filter parameters as key-value pairs.
    var parameters: [String: String]

    /// Position of this node on the canvas (in points).
    var position: CGPoint

    /// Number of input pads this node exposes.
    var inputCount: Int

    /// Number of output pads this node exposes.
    var outputCount: Int

    /// Creates a new filter node from a node type at the given position.
    init(
        type: FilterNodeType,
        position: CGPoint = CGPoint(x: 200, y: 200)
    ) {
        self.id = UUID()
        self.filterName = type.rawValue
        self.parameters = type.defaultParameters
        self.position = position
        self.inputCount = type.inputCount
        self.outputCount = type.outputCount
    }

    /// Creates a custom filter node with explicit parameters.
    init(
        id: UUID = UUID(),
        filterName: String,
        parameters: [String: String] = [:],
        position: CGPoint = .zero,
        inputCount: Int = 1,
        outputCount: Int = 1
    ) {
        self.id = id
        self.filterName = filterName
        self.parameters = parameters
        self.position = position
        self.inputCount = inputCount
        self.outputCount = outputCount
    }

    /// Equatable conformance (compare by id only).
    static func == (lhs: FilterNode, rhs: FilterNode) -> Bool {
        lhs.id == rhs.id
    }
}

// ---------------------------------------------------------------------------
// MARK: - FilterConnection
// ---------------------------------------------------------------------------
/// A directional connection between two filter nodes in the graph.
///
/// Represents a stream flowing from one node's output pad to another
/// node's input pad. Used to construct the FFmpeg filter chain string.
struct FilterConnection: Identifiable, Equatable, Sendable {

    /// Unique identifier for this connection.
    let id: UUID

    /// The source node's identifier.
    var sourceNode: UUID

    /// The output pad index on the source node (zero-based).
    var sourceOutput: Int

    /// The target node's identifier.
    var targetNode: UUID

    /// The input pad index on the target node (zero-based).
    var targetInput: Int

    init(
        id: UUID = UUID(),
        sourceNode: UUID,
        sourceOutput: Int = 0,
        targetNode: UUID,
        targetInput: Int = 0
    ) {
        self.id = id
        self.sourceNode = sourceNode
        self.sourceOutput = sourceOutput
        self.targetNode = targetNode
        self.targetInput = targetInput
    }
}

// ---------------------------------------------------------------------------
// MARK: - FilterGraph
// ---------------------------------------------------------------------------
/// Observable model that manages the complete visual filter graph state.
///
/// Holds all nodes and connections, provides methods for adding/removing
/// elements, and generates the FFmpeg `-vf` / `-af` filter string from
/// the current graph topology.
///
/// Thread safety: All mutations are `@MainActor`-isolated for SwiftUI
/// binding compatibility.
@MainActor
@Observable
final class FilterGraph {

    // MARK: - Properties

    /// All filter nodes in the graph.
    var nodes: [FilterNode] = []

    /// All connections between filter nodes.
    var connections: [FilterConnection] = []

    /// The currently selected node (for parameter editing).
    var selectedNodeID: UUID?

    // MARK: - Node Management

    /// Adds a new filter node of the specified type at the given canvas position.
    ///
    /// - Parameters:
    ///   - type: The built-in filter type to instantiate.
    ///   - position: Canvas position for the new node.
    func addNode(type: FilterNodeType, at position: CGPoint) {
        let node = FilterNode(type: type, position: position)
        nodes.append(node)
        selectedNodeID = node.id
    }

    /// Removes a node and all of its connections from the graph.
    ///
    /// - Parameter nodeID: The identifier of the node to remove.
    func removeNode(_ nodeID: UUID) {
        connections.removeAll { $0.sourceNode == nodeID || $0.targetNode == nodeID }
        nodes.removeAll { $0.id == nodeID }
        if selectedNodeID == nodeID {
            selectedNodeID = nil
        }
    }

    /// Updates the position of a node on the canvas (during drag).
    ///
    /// - Parameters:
    ///   - nodeID: The identifier of the node to move.
    ///   - position: The new canvas position.
    func moveNode(_ nodeID: UUID, to position: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].position = position
    }

    // MARK: - Connection Management

    /// Creates a connection between two nodes.
    ///
    /// Validates that both nodes exist and the pad indices are within
    /// range before creating the connection.
    ///
    /// - Parameters:
    ///   - sourceID: Source node identifier.
    ///   - sourceOutput: Output pad index on the source.
    ///   - targetID: Target node identifier.
    ///   - targetInput: Input pad index on the target.
    func connect(
        sourceID: UUID,
        sourceOutput: Int = 0,
        targetID: UUID,
        targetInput: Int = 0
    ) {
        // Validate nodes exist
        guard let source = nodes.first(where: { $0.id == sourceID }),
              let target = nodes.first(where: { $0.id == targetID }) else {
            return
        }

        // Validate pad indices
        guard sourceOutput < source.outputCount,
              targetInput < target.inputCount else {
            return
        }

        // Prevent duplicate connections to the same input
        guard !connections.contains(where: {
            $0.targetNode == targetID && $0.targetInput == targetInput
        }) else {
            return
        }

        let connection = FilterConnection(
            sourceNode: sourceID,
            sourceOutput: sourceOutput,
            targetNode: targetID,
            targetInput: targetInput
        )
        connections.append(connection)
    }

    /// Removes a connection from the graph.
    ///
    /// - Parameter connectionID: The identifier of the connection to remove.
    func removeConnection(_ connectionID: UUID) {
        connections.removeAll { $0.id == connectionID }
    }

    // MARK: - Filter String Generation

    /// Generates the FFmpeg filter string (`-vf` / `-af` value) from the
    /// current graph topology.
    ///
    /// Performs a topological sort of the nodes, then concatenates each
    /// node's filter expression with the appropriate link labels.
    ///
    /// For a simple linear chain `scale -> tonemap -> eq`, this produces:
    /// ```
    /// scale=w=1920:h=1080:flags=lanczos,tonemap=tonemap=hable:peak=100,eq=brightness=0:contrast=1:saturation=1
    /// ```
    ///
    /// - Returns: The complete filter string, or an empty string if the
    ///   graph has no nodes.
    func toFilterString() -> String {
        guard !nodes.isEmpty else { return "" }

        // Build adjacency for topological sort
        let sortedNodes = topologicallySortedNodes()

        // Generate filter expressions
        var filterParts: [String] = []

        for node in sortedNodes {
            var expr = node.filterName
            if !node.parameters.isEmpty {
                let paramStr = node.parameters
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ":")
                expr += "=\(paramStr)"
            }
            filterParts.append(expr)
        }

        return filterParts.joined(separator: ",")
    }

    // MARK: - Topological Sort

    /// Returns nodes in topological order based on the connection graph.
    ///
    /// Nodes with no incoming connections come first. If the graph is
    /// cyclic or disconnected, unvisited nodes are appended at the end
    /// in their original order.
    private func topologicallySortedNodes() -> [FilterNode] {
        var inDegree: [UUID: Int] = [:]
        var adjacency: [UUID: [UUID]] = [:]

        // Initialise
        for node in nodes {
            inDegree[node.id] = 0
            adjacency[node.id] = []
        }

        // Build edges
        for conn in connections {
            adjacency[conn.sourceNode, default: []].append(conn.targetNode)
            inDegree[conn.targetNode, default: 0] += 1
        }

        // Kahn's algorithm
        var queue: [UUID] = nodes.filter { inDegree[$0.id] == 0 }.map(\.id)
        var sorted: [UUID] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            sorted.append(current)

            for neighbour in adjacency[current, default: []] {
                inDegree[neighbour, default: 0] -= 1
                if inDegree[neighbour] == 0 {
                    queue.append(neighbour)
                }
            }
        }

        // Append any remaining nodes (disconnected or cyclic)
        for node in nodes where !sorted.contains(node.id) {
            sorted.append(node.id)
        }

        return sorted.compactMap { id in nodes.first(where: { $0.id == id }) }
    }

    /// The currently selected node, if any.
    var selectedNode: FilterNode? {
        guard let id = selectedNodeID else { return nil }
        return nodes.first { $0.id == id }
    }

    /// Clears the entire graph.
    func clearGraph() {
        nodes.removeAll()
        connections.removeAll()
        selectedNodeID = nil
    }
}

// ---------------------------------------------------------------------------
// MARK: - FilterGraphEditorView
// ---------------------------------------------------------------------------
/// Visual FFmpeg filter graph editor with a canvas-based node interface.
///
/// Provides a drag-and-drop palette of built-in FFmpeg filters, a zoomable
/// canvas where nodes can be positioned and connected, a parameter editor
/// for the selected node, and a live preview of the generated filter string.
///
/// Phase 12 — Visual FFmpeg Filter Graph Editor (Issue #354)
struct FilterGraphEditorView: View {

    // MARK: - State

    /// The filter graph model containing all nodes and connections.
    @State private var graph = FilterGraph()

    /// Current canvas zoom level (1.0 = 100%).
    @State private var canvasScale: CGFloat = 1.0

    /// Canvas scroll offset for panning.
    @State private var canvasOffset: CGSize = .zero

    /// Whether the palette sidebar is expanded.
    @State private var showPalette: Bool = true

    /// Whether the generated filter string was recently copied.
    @State private var didCopyFilterString: Bool = false

    /// Search text for filtering the palette.
    @State private var paletteSearchText: String = ""

    /// The node currently being dragged, if any.
    @State private var draggingNodeID: UUID?

    /// Temporary connection source for drawing new connections.
    @State private var connectionSource: (nodeID: UUID, outputIndex: Int)?

    // MARK: - Computed Properties

    /// Palette items filtered by search text.
    private var filteredPaletteItems: [FilterNodeType] {
        if paletteSearchText.isEmpty {
            return FilterNodeType.allCases
        }
        return FilterNodeType.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(paletteSearchText)
        }
    }

    /// Video filter types for palette grouping.
    private var videoFilters: [FilterNodeType] {
        filteredPaletteItems.filter { !$0.isAudioFilter }
    }

    /// Audio filter types for palette grouping.
    private var audioFilters: [FilterNodeType] {
        filteredPaletteItems.filter { $0.isAudioFilter }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // Left: Palette
            if showPalette {
                paletteView
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)
            }

            // Centre: Canvas
            VStack(spacing: 0) {
                canvasToolbar
                canvasView
                filterStringBar
            }
            .frame(minWidth: 400)

            // Right: Parameter editor
            if graph.selectedNode != nil {
                parameterEditorView
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            }
        }
        .frame(minHeight: 500)
    }

    // MARK: - Palette View

    /// Sidebar listing all available filter node types grouped by category.
    private var paletteView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Filter Palette")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            TextField("Search filters...", text: $paletteSearchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            List {
                if !videoFilters.isEmpty {
                    Section("Video Filters") {
                        ForEach(videoFilters) { filterType in
                            paletteItem(filterType)
                        }
                    }
                }
                if !audioFilters.isEmpty {
                    Section("Audio Filters") {
                        ForEach(audioFilters) { filterType in
                            paletteItem(filterType)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(.background)
    }

    /// A single draggable palette item.
    private func paletteItem(_ type: FilterNodeType) -> some View {
        HStack {
            Image(systemName: type.isAudioFilter ? "waveform" : "film")
                .foregroundStyle(type.isAudioFilter ? .purple : .blue)
                .frame(width: 20)
            Text(type.displayName)
                .font(.body)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Add the node at a default position offset by the current count
            let offset = CGFloat(graph.nodes.count) * 30
            graph.addNode(
                type: type,
                at: CGPoint(x: 300 + offset, y: 200 + offset)
            )
        }
        .help("Click to add \(type.displayName) filter to the canvas")
    }

    // MARK: - Canvas Toolbar

    /// Toolbar above the canvas with zoom controls and actions.
    private var canvasToolbar: some View {
        HStack {
            Button {
                showPalette.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle filter palette")

            Divider().frame(height: 16)

            Button {
                canvasScale = max(0.25, canvasScale - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Text("\(Int(canvasScale * 100))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 44)

            Button {
                canvasScale = min(3.0, canvasScale + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")

            Button {
                canvasScale = 1.0
                canvasOffset = .zero
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Reset zoom and position")

            Spacer()

            Text("\(graph.nodes.count) nodes, \(graph.connections.count) connections")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().frame(height: 16)

            Button(role: .destructive) {
                graph.clearGraph()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear all nodes and connections")
            .disabled(graph.nodes.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Canvas View

    /// The main filter graph canvas using SwiftUI Canvas for rendering
    /// nodes and connections.
    private var canvasView: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                canvasBackground

                // Connections
                ForEach(graph.connections) { connection in
                    connectionPath(connection)
                }

                // Nodes
                ForEach(graph.nodes, id: \.id) { node in
                    filterNodeView(node)
                        .position(
                            x: node.position.x * canvasScale + canvasOffset.width,
                            y: node.position.y * canvasScale + canvasOffset.height
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if draggingNodeID == nil {
                            canvasOffset = CGSize(
                                width: canvasOffset.width + value.translation.width,
                                height: canvasOffset.height + value.translation.height
                            )
                        }
                    }
            )
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Draws a subtle dot-grid background on the canvas.
    private var canvasBackground: some View {
        Canvas { context, size in
            let spacing: CGFloat = 20 * canvasScale
            let dotSize: CGFloat = 2
            let color = Color.secondary.opacity(0.2)

            var y: CGFloat = canvasOffset.height.truncatingRemainder(dividingBy: spacing)
            if y < 0 { y += spacing }

            while y < size.height {
                var x: CGFloat = canvasOffset.width.truncatingRemainder(dividingBy: spacing)
                if x < 0 { x += spacing }

                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: x - dotSize / 2,
                            y: y - dotSize / 2,
                            width: dotSize,
                            height: dotSize
                        )),
                        with: .color(color)
                    )
                    x += spacing
                }
                y += spacing
            }
        }
    }

    // MARK: - Node View

    /// Renders a single filter node on the canvas.
    private func filterNodeView(_ node: FilterNode) -> some View {
        let isSelected = graph.selectedNodeID == node.id

        return VStack(spacing: 4) {
            // Title bar
            HStack {
                Image(systemName: FilterNodeType(rawValue: node.filterName)?.isAudioFilter == true
                      ? "waveform" : "film")
                    .font(.caption)
                Text(FilterNodeType(rawValue: node.filterName)?.displayName ?? node.filterName)
                    .font(.caption.bold())
                Spacer()
                Button {
                    graph.removeNode(node.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))

            // Parameter summary
            if !node.parameters.isEmpty {
                let summary = node.parameters
                    .sorted { $0.key < $1.key }
                    .prefix(3)
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }

            // Input/output indicators
            HStack {
                ForEach(0..<node.inputCount, id: \.self) { idx in
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .help("Input \(idx)")
                }
                Spacer()
                ForEach(0..<node.outputCount, id: \.self) { idx in
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .help("Output \(idx)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(color: isSelected ? .accentColor.opacity(0.4) : .black.opacity(0.15), radius: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            graph.selectedNodeID = node.id
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    draggingNodeID = node.id
                    graph.moveNode(node.id, to: CGPoint(
                        x: (value.location.x - canvasOffset.width) / canvasScale,
                        y: (value.location.y - canvasOffset.height) / canvasScale
                    ))
                }
                .onEnded { _ in
                    draggingNodeID = nil
                }
        )
        .scaleEffect(canvasScale)
    }

    // MARK: - Connection Rendering

    /// Draws a curved path between two connected nodes.
    private func connectionPath(_ connection: FilterConnection) -> some View {
        let sourceNode = graph.nodes.first { $0.id == connection.sourceNode }
        let targetNode = graph.nodes.first { $0.id == connection.targetNode }

        return Path { path in
            guard let source = sourceNode, let target = targetNode else { return }

            let startX = source.position.x * canvasScale + canvasOffset.width + 90
            let startY = source.position.y * canvasScale + canvasOffset.height
            let endX = target.position.x * canvasScale + canvasOffset.width - 90
            let endY = target.position.y * canvasScale + canvasOffset.height

            let controlOffset = abs(endX - startX) * 0.5

            path.move(to: CGPoint(x: startX, y: startY))
            path.addCurve(
                to: CGPoint(x: endX, y: endY),
                control1: CGPoint(x: startX + controlOffset, y: startY),
                control2: CGPoint(x: endX - controlOffset, y: endY)
            )
        }
        .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
    }

    // MARK: - Parameter Editor

    /// Right-side panel for editing the selected node's parameters.
    private var parameterEditorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedID = graph.selectedNodeID,
               let nodeIndex = graph.nodes.firstIndex(where: { $0.id == selectedID }) {

                let node = graph.nodes[nodeIndex]

                Text("Parameters")
                    .font(.headline)

                Text(FilterNodeType(rawValue: node.filterName)?.displayName ?? node.filterName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        let sortedKeys = node.parameters.keys.sorted()
                        ForEach(sortedKeys, id: \.self) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    key,
                                    text: Binding(
                                        get: { graph.nodes[nodeIndex].parameters[key] ?? "" },
                                        set: { graph.nodes[nodeIndex].parameters[key] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                            }
                        }
                    }
                }

                Divider()

                // Connection controls
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connections")
                        .font(.caption.bold())

                    let incoming = graph.connections.filter { $0.targetNode == selectedID }
                    let outgoing = graph.connections.filter { $0.sourceNode == selectedID }

                    Text("Inputs: \(incoming.count) / \(node.inputCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Outputs: \(outgoing.count) / \(node.outputCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    graph.removeNode(selectedID)
                } label: {
                    Label("Remove Node", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.background)
    }

    // MARK: - Filter String Bar

    /// Bottom bar showing the live-generated filter string with a copy button.
    private var filterStringBar: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)

            let filterString = graph.toFilterString()

            Text(filterString.isEmpty ? "Add filters to generate a string" : filterString)
                .font(.body.monospaced())
                .lineLimit(2)
                .foregroundStyle(filterString.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)

            Spacer()

            Button {
                let str = graph.toFilterString()
                guard !str.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
                didCopyFilterString = true

                // Reset the copy confirmation after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    didCopyFilterString = false
                }
            } label: {
                Label(
                    didCopyFilterString ? "Copied!" : "Copy Filter String",
                    systemImage: didCopyFilterString ? "checkmark" : "doc.on.doc"
                )
            }
            .disabled(graph.toFilterString().isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Preview
// ---------------------------------------------------------------------------
#if DEBUG
#Preview("Filter Graph Editor") {
    FilterGraphEditorView()
        .frame(width: 900, height: 600)
}
#endif
