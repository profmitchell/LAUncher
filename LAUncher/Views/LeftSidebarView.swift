import SwiftUI

struct LeftSidebarView: View {
    @ObservedObject var session: PluginHostSession
    
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
            
            // Transport & Engine
            VStack(alignment: .leading, spacing: 12) {
                Text("Transport")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Label("BPM", systemImage: "metronome")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("BPM", value: $session.bpm, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Stepper("", value: Binding(get: { Int(session.bpm) }, set: { session.bpm = Double($0) }), in: 10...400)
                        .labelsHidden()
                }
                
                Button {
                    session.toggleTransport()
                } label: {
                    Label(session.isTransportPlaying ? "Pause" : "Play",
                          systemImage: session.isTransportPlaying ? "pause.circle" : "play.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(engineIndicatorColor)
                        .frame(width: 10, height: 10)
                    Text(engineStatusText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        session.toggleEngineRunning()
                    } label: {
                        Label(session.engineState == .running ? "Stop" : "Start",
                              systemImage: session.engineState == .running ? "stop.circle" : "play.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            
            Divider()
            
            // Quick actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Tools")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
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
        .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
        .background(.ultraThinMaterial)
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
        case .error(let message):
            return "Error"
        }
    }
}

