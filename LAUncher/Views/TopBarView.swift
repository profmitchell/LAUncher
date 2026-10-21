import SwiftUI
import AVFAudio

/// Slim host toolbar — identity, transport, and a few clear actions.
struct TopBarView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject var themeManager: ThemeManager

    init(session: PluginHostSession) {
        self.session = session
        self.themeManager = session.themeManager
    }

    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        HStack(spacing: 14) {
            identity

            Divider().frame(height: 18)

            transport

            Spacer(minLength: 8)

            if session.currentComponent != nil {
                Button {
                    session.unloadCurrentInstrument()
                } label: {
                    Text("Unload")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                session.isLibraryVisible.toggle()
            } label: {
                Label(
                    session.isLibraryVisible ? "Hide Library" : "Library",
                    systemImage: "sidebar.left"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Show or hide the plugin library")

            Button {
                session.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Audio, MIDI, sample rate (⌘,)")

            moreMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(LauncherChrome.barBackground(theme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LauncherChrome.border(theme).opacity(0.55))
                .frame(height: 1)
        }
    }

    private var identity: some View {
        HStack(spacing: 8) {
            Text("LAUncher")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(LauncherChrome.textMain(theme))

            if let component = session.currentComponent {
                Text(component.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LauncherChrome.textMuted(theme))
                    .lineLimit(1)
            } else {
                Text("No plugin")
                    .font(.system(size: 13))
                    .foregroundStyle(LauncherChrome.textMuted(theme).opacity(0.7))
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                session.toggleTransport()
            } label: {
                Image(systemName: session.isTransportPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(session.isTransportPlaying ? "Pause transport" : "Play transport")

            TextField("BPM", value: $session.bpm, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .font(.system(size: 12).monospacedDigit())
                .help("Tempo")

            Circle()
                .fill(engineColor)
                .frame(width: 7, height: 7)
                .help(engineHelp)

            Button {
                session.toggleEngineRunning()
            } label: {
                Text(session.engineManager.isRunning ? "Audio On" : "Audio Off")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(session.engineManager.isRunning ? .green : LauncherChrome.textMuted(theme))
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Load Plugin…") {
                session.refreshPluginList()
                session.isShowingPluginPicker = true
            }
            Button {
                session.rescanPlugins()
            } label: {
                Text(session.isRescanning ? "Rescanning…" : "Rescan Plugins")
            }
            .disabled(session.isRescanning)

            Toggle("QWERTY Piano", isOn: $session.isMusicalTypingEnabled)
            if session.isMusicalTypingEnabled {
                Toggle("Show QWERTY Piano", isOn: $session.isMusicalTypingVisible)
            }

            if session.currentComponent != nil {
                Divider()
                Button("MIDI Learn…") { session.isShowingMIDIMap = true }
                Button("Export Parameters…") { session.exportParametersAsJSON() }
                Divider()
                Button("Set as Default Plugin") {
                    if let c = session.currentComponent { session.setDefaultPlugin(c) }
                }
                Button("Clear Default Plugin") { session.clearDefaultPlugin() }
            }

            Divider()
            Button("Help") { session.isShowingHelp = true }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28, height: 28)
        .help("More")
    }

    private var engineColor: Color {
        switch session.engineState {
        case .running: return .green
        case .stopped: return .secondary
        case .error: return .red
        }
    }

    private var engineHelp: String {
        switch session.engineState {
        case .running: return "Audio engine running"
        case .stopped: return "Audio engine stopped"
        case .error: return "Audio engine error"
        }
    }
}
