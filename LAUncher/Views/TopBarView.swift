import SwiftUI
import AVFAudio

struct TopBarView: View {
    @ObservedObject var session: PluginHostSession
    var expanded: Bool = false
    @State private var showIOPopover = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, expanded ? 12 : 8)
        }
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1), alignment: .bottom)
        .controlSize(expanded ? .large : .regular)
    }

    // MARK: - Layout
    private var content: some View {
        Group {
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        titleArea
                        Spacer()
                        actionButtons
                    }
                    HStack(spacing: 16) {
                        engineControls
                        ioButton
                        Spacer(minLength: 8)
                        musicalTypingToggle
                        moreMenu
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        titleArea
                        Spacer(minLength: 12)
                        actionButtons
                        engineControls
                        ioButton
                        musicalTypingToggle
                        moreMenu
                    }
                }
            }
        }
    }

    private var titleArea: some View {
        HStack(spacing: 8) {
            Text("Mini AU Host")
                .font(.headline)
                .foregroundStyle(.primary)
            if let component = session.currentComponent {
                Text("• \(component.name)")
                    .foregroundStyle(.secondary)
            } else {
                Text("• No plugin loaded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                session.refreshInstrumentList()
                session.refreshPluginList()
                session.isShowingPluginPicker = true
            } label: {
                Label("Load Plugin…", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var ioButton: some View {
        Button {
            showIOPopover.toggle()
        } label: {
            Label("I/O", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showIOPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                audioControls
                Divider()
                midiControls
            }
            .padding(12)
            .frame(width: 460)
        }
        .help("Audio and MIDI device selection")
    }

    private var moreMenu: some View {
        Menu {
            Button("Rescan Plugins", systemImage: "arrow.clockwise") { session.rescanPlugins() }
            if session.currentComponent != nil {
                Button("Unload Plugin", systemImage: "eject") { session.unloadCurrentInstrument() }
                Divider()
                Button("Export Parameters", systemImage: "doc.text") { session.exportParametersAsJSON() }
                Button("MCP Tools", systemImage: "wand.and.stars") { session.isShowingMCPTools = true }
                Button("MIDI Learn", systemImage: "keyboard") { session.isShowingMIDIMap = true }
                Button("AI Chat", systemImage: "message.fill") { session.isShowingChat = true }
                Divider()
                Button("Set as Default", systemImage: "star") {
                    if let c = session.currentComponent { session.setDefaultPlugin(c) }
                }
                Button("Clear Default", systemImage: "star.slash") { session.clearDefaultPlugin() }
            }
            Divider()
            if session.isMusicalTypingVisible {
                Button("Hide On-screen Keyboard", systemImage: "eye.slash") { session.isMusicalTypingVisible = false }
            } else {
                Button("Show On-screen Keyboard", systemImage: "eye") { session.isMusicalTypingVisible = true }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .buttonStyle(.bordered)
    }

    private var engineControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(engineIndicatorColor)
                    .frame(width: 10, height: 10)
                Text(engineStatusText)
                    .foregroundStyle(.secondary)
            }

            Button {
                session.toggleEngineRunning()
            } label: {
                Label(session.engineState == .running ? "Stop Audio" : "Start Audio",
                      systemImage: session.engineState == .running ? "stop.circle" : "play.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var audioControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Label("Input", systemImage: "mic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Input", selection: $session.selectedInputDevice) {
                    Text("None").tag(Optional<AudioDevice>.none)
                    ForEach(session.inputDevices) { device in
                        Text(device.name).tag(Optional(device))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            
            HStack(spacing: 8) {
                // OUTPUT 1 (stereo)
                Label("Output 1", systemImage: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Output 1", selection: $session.selectedOutput1) {
                    Text("None").tag(Optional<AudioDevice>.none)
                    ForEach(session.outputDevices) { device in
                        Text(device.name).tag(Optional(device))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                
                // OUTPUT 2 (stereo)
                Label("Output 2", systemImage: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Output 2", selection: $session.selectedOutput2) {
                    Text("None").tag(Optional<AudioDevice>.none)
                    ForEach(session.outputDevices) { device in
                        Text(device.name).tag(Optional(device))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            
            Button {
                session.audioDeviceManager.refreshDevices()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh audio devices")
        }
    }

    private var midiControls: some View {
        HStack(spacing: 8) {
            Picker("MIDI Input", selection: $session.selectedMidiSource) {
                Text("All Available").tag(Optional<MidiSource>.none)
                ForEach(session.midiSources) { source in
                    Text(source.name).tag(Optional(source))
                }
            }
            .pickerStyle(.menu)

            Button {
                session.midiManager.refreshSources()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh MIDI devices")
        }
    }

    private var musicalTypingToggle: some View {
        Toggle(isOn: $session.isMusicalTypingEnabled) {
            Label("Musical Typing", systemImage: "keyboard")
                .labelStyle(.iconOnly)
        }
        .toggleStyle(.button)
        .help("Show on-screen keyboard for typing notes")
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
            return "Engine Running"
        case .stopped:
            return "Engine Stopped"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
