import SwiftUI
import AVFAudio

struct TopBarView: View {
    @ObservedObject var session: PluginHostSession

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.4)
            HStack(spacing: 16) {
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

                Spacer()

                Button {
                    session.refreshInstrumentList()
                    session.refreshPluginList()
                    session.isShowingPluginPicker = true
                } label: {
                    Label("Load Plugin…", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    session.rescanPlugins()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Rescan for new plugins")

                if session.currentComponent != nil {
                    Button {
                        session.unloadCurrentInstrument()
                    } label: {
                        Label("Unload", systemImage: "eject")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        session.exportParametersAsJSON()
                    } label: {
                        Label("Export Params", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .help("Export plugin parameters as JSON")
                    
                    Button {
                        session.isShowingMCPTools = true
                    } label: {
                        Label("MCP Tools", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .help("Open MCP tools for intelligent parameter control")
                    
                    Button {
                        session.isShowingMIDIMap = true
                    } label: {
                        Label("MIDI Learn", systemImage: "keyboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Map MIDI CC controllers to parameters")
                }

                engineControls
                audioControls
                midiControls
                musicalTypingToggle
            }
            .padding(12)
            Divider()
                .opacity(0.4)
        }
        .background(.ultraThinMaterial)
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
