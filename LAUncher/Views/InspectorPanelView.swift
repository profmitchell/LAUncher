import SwiftUI

struct InspectorPanelView: View {
    @ObservedObject var session: PluginHostSession
    @State private var selection: Tab = .io

    enum Tab: String, CaseIterable { case io = "I/O", midi = "MIDI" }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
                Button {
                    session.isShowingInspector = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            Divider()

            // Tab Picker
            Picker("", selection: $selection) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            // Content
            Group {
                switch selection {
                case .io:
                    ioView
                case .midi:
                    midiView
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 200, idealWidth: 320, maxWidth: 500)
        .background(session.themeManager.currentTheme.materialStyle.material)
    }

    private var ioView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Devices").font(.headline)
            HStack {
                Text("Input").frame(width: 60, alignment: .leading)
                Picker("Input", selection: $session.selectedInputDevice) {
                    Text("None").tag(Optional<AudioDevice>.none)
                    ForEach(session.inputDevices) { device in
                        Text(device.name).tag(Optional(device))
                    }
                }
                .pickerStyle(.menu)
                Button { session.audioDeviceManager.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
            }
            HStack {
                Text("Output").frame(width: 60, alignment: .leading)
                Picker("Output", selection: $session.selectedOutputDevice) {
                    Text("None").tag(Optional<AudioDevice>.none)
                    ForEach(session.outputDevices) { device in
                        Text(device.name).tag(Optional(device))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var midiView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIDI").font(.headline)
            HStack {
                Text("Input").frame(width: 60, alignment: .leading)
                Picker("MIDI Input", selection: $session.selectedMidiSource) {
                    Text("All Available").tag(Optional<MidiSource>.none)
                    ForEach(session.midiSources) { source in
                        Text(source.name).tag(Optional(source))
                    }
                }
                .pickerStyle(.menu)
                Button { session.midiManager.refreshSources() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}


