import SwiftUI
import AVFoundation

struct MIDIMapView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedParameter: AUParameter?
    @State private var searchText: String = ""
    @State private var mappingSearchText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 500)
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
                    Text("Move CC \(pendingCC) → Interact with a parameter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Move a MIDI controller, then interact with a parameter")
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

