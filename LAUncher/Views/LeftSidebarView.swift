import SwiftUI
import AVFoundation

struct LeftSidebarView: View {
    @ObservedObject var session: PluginHostSession
    @State private var pluginSearchText = ""
    @State private var selectedScope: SidebarPluginScope = .all
    @State private var loadingComponent: AVAudioUnitComponent?

    private enum SidebarPluginScope: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        case instruments = "Inst"
        case effects = "FX"

        var id: String { rawValue }
    }

    private var pluginSource: [AVAudioUnitComponent] {
        let components = session.availablePlugins.isEmpty ? session.availableInstruments : session.availablePlugins
        switch selectedScope {
        case .all:
            return components
        case .recent:
            return session.recentPluginComponents
        case .instruments:
            return components.filter { $0.audioComponentDescription.componentType == kAudioUnitType_MusicDevice }
        case .effects:
            return components.filter { $0.audioComponentDescription.componentType == kAudioUnitType_Effect }
        }
    }

    private var filteredPlugins: [AVAudioUnitComponent] {
        let sorted = pluginSource.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        guard !pluginSearchText.isEmpty else { return sorted }
        return sorted.filter { component in
            component.name.localizedCaseInsensitiveContains(pluginSearchText) ||
            component.manufacturerName.localizedCaseInsensitiveContains(pluginSearchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Plugin controls
            VStack(alignment: .leading, spacing: 12) {
                Text("Plugin")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Button {
                    session.refreshInstrumentList()
                    session.refreshPluginList()
                    session.isShowingPluginPicker = true
                } label: {
                    Label("Load Plugin…", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                
                if session.currentComponent != nil {
                    Button {
                        session.unloadCurrentInstrument()
                    } label: {
                        Label("Unload", systemImage: "eject")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Plugin Browser")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        session.rescanPlugins()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Rescan plugins")
                }

                TextField("Search plugins", text: $pluginSearchText)
                    .textFieldStyle(.roundedBorder)

                Picker("Plugin type", selection: $selectedScope) {
                    ForEach(SidebarPluginScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if filteredPlugins.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                Text(pluginSearchText.isEmpty ? "No plugins found" : "No matches")
                                    .font(.callout.weight(.medium))
                                Text(pluginSearchText.isEmpty ? "Try rescanning Audio Units." : "Change the search or filter.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                        } else {
                            ForEach(filteredPlugins, id: \.self) { component in
                                SidebarPluginRow(
                                    component: component,
                                    isCurrent: session.currentComponent == component,
                                    isLoading: loadingComponent == component,
                                    typeLabel: componentTypeLabel(component)
                                ) {
                                    load(component)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.visible)
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .layoutPriority(1)

            Divider()

            // Transport & Engine
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        session.toggleTransport()
                    } label: {
                        Image(systemName: session.isTransportPlaying ? "pause.circle" : "play.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .help(session.isTransportPlaying ? "Pause" : "Play")

                    TextField("BPM", value: $session.bpm, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                        .help("BPM")

                    Stepper("", value: Binding(get: { Int(session.bpm) }, set: { session.bpm = Double($0) }), in: 10...400)
                        .labelsHidden()

                    Spacer()

                    Circle()
                        .fill(engineIndicatorColor)
                        .frame(width: 9, height: 9)

                    Button {
                        session.toggleEngineRunning()
                    } label: {
                        Text(session.engineState == .running ? "Stop" : "Start")
                    }
                    .buttonStyle(.bordered)
                    .help(engineStatusText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Quick actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Tools")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Button {
                    session.showPresetBrowser()
                } label: {
                    Label("Preset Browser", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                
                if session.currentComponent != nil {
                    Button {
                        session.isShowingMIDIMap = true
                    } label: {
                        Label("MIDI Learn", systemImage: "keyboard")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        session.isShowingMCPTools = true
                    } label: {
                        Label("MCP Tools", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        session.isShowingChat = true
                    } label: {
                        Label("AI Chat", systemImage: "message.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                
                Toggle(isOn: $session.isMusicalTypingEnabled) {
                    Label("QWERTY Piano", systemImage: "keyboard")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.button)
            }
            .padding(16)
            
            Spacer()
        }
        .frame(minWidth: 220, idealWidth: 320, maxWidth: 420)
        .background(.ultraThinMaterial)
    }

    private func load(_ component: AVAudioUnitComponent) {
        guard loadingComponent == nil, session.currentComponent != component else { return }
        loadingComponent = component

        Task { @MainActor in
            defer { loadingComponent = nil }
            await session.load(component: component)
        }
    }

    private func componentTypeLabel(_ component: AVAudioUnitComponent) -> String {
        switch component.audioComponentDescription.componentType {
        case kAudioUnitType_MusicDevice: return "Instrument"
        case kAudioUnitType_Effect: return "Effect"
        case kAudioUnitType_Generator: return "Generator"
        case kAudioUnitType_Mixer: return "Mixer"
        case kAudioUnitType_Panner: return "Panner"
        case kAudioUnitType_FormatConverter: return "Format"
        case kAudioUnitType_OfflineEffect: return "Offline"
        default: return component.typeName
        }
    }
    
    private var engineIndicatorColor: Color {
        switch session.engineState {
        case .running:
            return .green
        case .stopped:
            return .gray
        case .error:
            return .red
        }
    }
    
    private var engineStatusText: String {
        switch session.engineState {
        case .running:
            return "Running"
        case .stopped:
            return "Stopped"
        case .error:
            return "Error"
        }
    }
}

private struct SidebarPluginRow: View {
    let component: AVAudioUnitComponent
    let isCurrent: Bool
    let isLoading: Bool
    let typeLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    Text(component.name)
                        .font(.callout.weight(isCurrent ? .semibold : .regular))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(component.manufacturerName)
                            .lineLimit(1)
                        Text("·")
                        Text(typeLabel)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    @ViewBuilder
    private var icon: some View {
        if let nsImage = component.icon {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.quaternary)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                )
        }
    }

    private var systemImage: String {
        switch component.audioComponentDescription.componentType {
        case kAudioUnitType_MusicDevice: return "pianokeys"
        case kAudioUnitType_Effect: return "slider.horizontal.3"
        case kAudioUnitType_Generator: return "waveform"
        default: return "waveform.path"
        }
    }
}
