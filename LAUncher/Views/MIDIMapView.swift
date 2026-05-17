import SwiftUI
import AVFoundation

struct MIDIMapView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedParameter: AUParameter?
    @State private var searchText: String = ""
    @State private var mappingSearchText: String = ""
    @State private var matrixSearchText: String = ""
    @State private var selectedMode: MIDIMappingMode = .learn
    @State private var selectedMatrixCC: UInt8 = 1
    @State private var selectedMatrixParameterId: String = ""

    private enum MIDIMappingMode: String, CaseIterable, Identifiable {
        case learn = "Learn"
        case matrix = "Matrix"

        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("View", selection: $selectedMode) {
                ForEach(MIDIMappingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)
            Divider()
            if selectedMode == .learn {
                content
            } else {
                matrixContent
            }
            Divider()
            footer
        }
        .frame(minWidth: 860, minHeight: 620)
        .onAppear {
            if selectedMatrixParameterId.isEmpty,
               let firstParameter = session.getCurrentParameters()?.first {
                selectedMatrixParameterId = firstParameter.identifier
            }
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MIDI Learn & Mapping")
                    .font(.title2.weight(.medium))
                Text("Map MIDI CC controllers to plugin parameters")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var content: some View {
        HStack(spacing: 0) {
            // Left: Parameter list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Parameters")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                
                // Search bar
                TextField("Search parameters...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Divider()
                
                ScrollView {
                    if let params = session.getCurrentParameters() {
                        let filteredParams = filteredParameters(params)
                        if filteredParams.isEmpty {
                            Text("No parameters match \"\(searchText)\"")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            LazyVStack(spacing: 4) {
                                ForEach(filteredParams, id: \.identifier) { param in
                                    ParameterMapRow(
                                        param: param,
                                        isSelected: selectedParameter?.identifier == param.identifier,
                                        mapping: session.midiMapManager.mappings.first(where: { $0.parameterId == param.identifier }),
                                        onSelect: { selectedParameter = param },
                                        onLearn: {
                                            session.midiMapManager.startLearning(parameterId: param.identifier)
                                        },
                                        isLearning: session.midiMapManager.isLearning && session.midiMapManager.learningParameterId == param.identifier
                                    )
                                }
                            }
                            .padding()
                        }
                    } else {
                        Text("No parameters available")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            .frame(width: 300)
            
            Divider()
            
            // Right: Mappings list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("MIDI Mappings")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                
                // Search bar for mappings
                TextField("Search mappings...", text: $mappingSearchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Divider()
                
                ScrollView {
                    let filteredMappings = filteredMappings()
                    if filteredMappings.isEmpty {
                        if session.midiMapManager.mappings.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("No MIDI mappings")
                                    .font(.headline)
                                Text("Turn on Learn Mode or select a parameter and click 'Learn' to create a mapping")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            Text("No mappings match \"\(mappingSearchText)\"")
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredMappings) { mapping in
                                MappingRow(
                                    mapping: mapping,
                                    parameter: session.findParameter(identifier: mapping.parameterId),
                                    onRemove: {
                                        session.midiMapManager.removeMapping(mapping)
                                    },
                                    onUpdateRange: { minVal, maxVal in
                                        session.midiMapManager.updateMapping(mapping, minValue: minVal, maxValue: maxVal)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var matrixContent: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Mapping Matrix")
                        .font(.headline)
                    Spacer()
                    if let last = session.midiMapManager.lastCCReceived {
                        Button("Use Last CC \(last)") {
                            selectedMatrixCC = last
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Filter CC or parameter", text: $matrixSearchText)
                        .textFieldStyle(.roundedBorder)

                    Stepper("CC \(selectedMatrixCC)", value: Binding(
                        get: { Int(selectedMatrixCC) },
                        set: { selectedMatrixCC = UInt8(clamping: $0) }
                    ), in: 0...127)
                    .frame(width: 120)
                }

                HStack(spacing: 8) {
                    Picker("Parameter", selection: $selectedMatrixParameterId) {
                        if let params = session.getCurrentParameters() {
                            ForEach(params, id: \.identifier) { param in
                                Text(param.displayName).tag(param.identifier)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        addMatrixMapping()
                    } label: {
                        Label("Map", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedMatrixParameterId.isEmpty)
                }

                Divider()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredMatrixCCs, id: \.self) { cc in
                            MatrixCCRow(
                                ccNumber: UInt8(cc),
                                mappings: session.midiMapManager.mappings(forCC: UInt8(cc)),
                                parameterLookup: { session.findParameter(identifier: $0) },
                                isSelected: selectedMatrixCC == UInt8(cc),
                                onSelect: { selectedMatrixCC = UInt8(cc) },
                                onRemove: { mapping in session.midiMapManager.removeMapping(mapping) },
                                onClear: { session.midiMapManager.removeMappings(forCC: UInt8(cc)) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .frame(minWidth: 560, maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Learn Status")
                    .font(.headline)

                statusLine(
                    title: "Last CC",
                    value: session.midiMapManager.lastCCReceived.map { "CC \($0)" } ?? "None"
                )
                statusLine(
                    title: "Pending",
                    value: session.midiMapManager.pendingCCForLearnMode.map { "CC \($0)" } ?? "None"
                )
                statusLine(
                    title: "Mappings",
                    value: "\(session.midiMapManager.mappings.count)"
                )

                Divider()

                Text("Matrix rows are MIDI CC numbers. Each chip is a plugin parameter currently mapped to that CC. Select a row, choose a parameter, then Map.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding()
            .frame(width: 240)
        }
    }

    private var filteredMatrixCCs: [Int] {
        let allCCs = Array(0...127)
        guard !matrixSearchText.isEmpty else { return allCCs }
        let lower = matrixSearchText.lowercased()
        return allCCs.filter { cc in
            String(cc).contains(lower) ||
            session.midiMapManager.mappings(forCC: UInt8(cc)).contains { mapping in
                mapping.parameterDisplayName.lowercased().contains(lower) ||
                mapping.parameterId.lowercased().contains(lower)
            }
        }
    }

    private func addMatrixMapping() {
        guard let param = session.findParameter(identifier: selectedMatrixParameterId) else { return }
        session.midiMapManager.createMapping(
            parameterId: param.identifier,
            parameterDisplayName: param.displayName,
            ccNumber: selectedMatrixCC,
            minValue: param.minValue,
            maxValue: param.maxValue
        )
    }

    private func statusLine(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
        }
    }
    
    private func filteredParameters(_ params: [AUParameter]) -> [AUParameter] {
        if searchText.isEmpty {
            return params
        }
        let lowerSearch = searchText.lowercased()
        return params.filter { param in
            param.displayName.lowercased().contains(lowerSearch) ||
            param.identifier.lowercased().contains(lowerSearch)
        }
    }
    
    private func filteredMappings() -> [MIDIMapping] {
        if mappingSearchText.isEmpty {
            return session.midiMapManager.mappings
        }
        let lowerSearch = mappingSearchText.lowercased()
        return session.midiMapManager.mappings.filter { mapping in
            mapping.parameterDisplayName.lowercased().contains(lowerSearch) ||
            String(mapping.ccNumber).contains(lowerSearch) ||
            mapping.parameterId.lowercased().contains(lowerSearch)
        }
    }
    
    private var footer: some View {
        HStack {
            // Learn Mode Toggle
            Button {
                session.midiMapManager.toggleLearnMode()
            } label: {
                HStack {
                    Circle()
                        .fill(session.midiMapManager.isInLearnMode ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text("LEARN MODE")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .tint(session.midiMapManager.isInLearnMode ? .green : .gray)
            
            if session.midiMapManager.isInLearnMode {
                if let pendingCC = session.midiMapManager.pendingCCForLearnMode {
                    Text("CC \(pendingCC) → Click a parameter in the plugin UI")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Move a MIDI controller, then click a parameter in the plugin UI")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if session.midiMapManager.isLearning {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: session.midiMapManager.isLearning)
                    Text("Move a MIDI controller to learn...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                session.midiMapManager.cancelLearning()
            } label: {
                Text("Cancel Learn")
            }
            .buttonStyle(.bordered)
            .disabled(!session.midiMapManager.isLearning)
            
            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct ParameterMapRow: View {
    let param: AUParameter
    let isSelected: Bool
    let mapping: MIDIMapping?
    let onSelect: () -> Void
    let onLearn: () -> Void
    let isLearning: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(param.displayName)
                    .font(.subheadline.weight(.medium))
                Text(param.identifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let mapping {
                Text("CC \(mapping.ccNumber)")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }
            
            if isLearning {
                Button {
                    // Cancel learn
                } label: {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    onLearn()
                } label: {
                    Image(systemName: mapping != nil ? "pencil.circle" : "plus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            onSelect()
        }
    }
}

struct MappingRow: View {
    let mapping: MIDIMapping
    let parameter: AUParameter?
    let onRemove: () -> Void
    let onUpdateRange: (Float, Float) -> Void
    
    @State private var showingRangeEditor = false
    @State private var minValue: Float
    @State private var maxValue: Float
    
    init(mapping: MIDIMapping, parameter: AUParameter?, onRemove: @escaping () -> Void, onUpdateRange: @escaping (Float, Float) -> Void) {
        self.mapping = mapping
        self.parameter = parameter
        self.onRemove = onRemove
        self.onUpdateRange = onUpdateRange
        _minValue = State(initialValue: mapping.minValue)
        _maxValue = State(initialValue: mapping.maxValue)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parameter?.displayName ?? mapping.parameterDisplayName)
                        .font(.subheadline.weight(.medium))
                    Text("CC \(mapping.ccNumber)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            
            if showingRangeEditor {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Range:")
                            .font(.caption)
                        TextField("Min", value: $minValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("to")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Max", value: $maxValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        
                        Button("Apply") {
                            onUpdateRange(minValue, maxValue)
                            showingRangeEditor = false
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Cancel") {
                            minValue = mapping.minValue
                            maxValue = mapping.maxValue
                            showingRangeEditor = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            } else {
                Text("Range: \(mapping.minValue, specifier: "%.2f") - \(mapping.maxValue, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button {
                    showingRangeEditor = true
                } label: {
                    Text("Edit Range")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

private struct MatrixCCRow: View {
    let ccNumber: UInt8
    let mappings: [MIDIMapping]
    let parameterLookup: (String) -> AUParameter?
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: (MIDIMapping) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onSelect) {
                VStack(spacing: 2) {
                    Text("CC")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(ccNumber)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .frame(width: 52, height: 46)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if mappings.isEmpty {
                Text("No mappings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 15)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(mappings) { mapping in
                        MatrixMappingChip(
                            title: parameterLookup(mapping.parameterId)?.displayName ?? mapping.parameterDisplayName,
                            subtitle: mapping.parameterId,
                            onRemove: { onRemove(mapping) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(role: .destructive, action: onClear) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear all CC \(ccNumber) mappings")
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(isSelected ? 0.75 : 0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MatrixMappingChip: View {
    let title: String
    let subtitle: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.isEmpty ? subtitle : title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
