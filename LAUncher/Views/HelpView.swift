import SwiftUI

struct HelpView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("LAUncher Help")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section(title: "Getting Started", icon: "play.circle.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "Load a Plugin", description: "Open the Library sidebar or choose Browse Plugins… to load an Audio Unit.")
                            helpItem(title: "Audio", description: "Use Audio On in the toolbar, or open Settings (⌘,) for devices and sample rate.")
                            helpItem(title: "Play Notes", description: "Enable QWERTY Piano from the More menu, or connect a MIDI controller.")
                        }
                    }

                    section(title: "QWERTY Piano", icon: "keyboard") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "Note keys", description: "A = C of the current octave. Whites: A S D F G H J K L ; '  ·  Blacks: W E T Y U O P")
                            helpItem(title: "Octave", description: "Z = octave down, X = octave up, C = center on Middle C.")
                            helpItem(title: "Sustain", description: "Tab toggles sustain. Notes stay held until sustain is turned off.")
                            helpItem(title: "Velocity", description: "Use the Vel slider, or press , / . to nudge velocity. Typing is ignored while a text field is focused.")
                        }
                    }

                    section(title: "Key Features", icon: "star.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "QWERTY Piano", description: "Computer-keyboard MIDI. Toggle from More; drag the floating piano by its title bar.")
                            helpItem(title: "MIDI Learn", description: "Map MIDI CC to plugin parameters from More → MIDI Learn…")
                            helpItem(title: "BPM Sync", description: "Set BPM in the toolbar. Tempo-synced effects follow host transport.")
                            helpItem(title: "Rescan Plugins", description: "More → Rescan Plugins after installing new Audio Units.")
                            helpItem(title: "Settings", description: "⌘, for output/input, sample rate, MIDI, and theme. If an effect won’t load, try 48 kHz.")
                        }
                    }

                    section(title: "Tips", icon: "lightbulb.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "Library", description: "The library hides after you load a plugin. Use Library in the toolbar to bring it back.")
                            helpItem(title: "Default Plugin", description: "More → Set as Default Plugin to auto-load on launch.")
                            helpItem(title: "Master Gain", description: "Bottom status bar controls master output volume.")
                        }
                    }

                    section(title: "Credits", icon: "person.fill") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("**LAUncher**")
                                .font(.headline)
                            Text("Developed and maintained by **Mitchell Cohen**")
                            Text("Professor of Sound Design & Production @ Berklee College of Music")
                            Text("2026 Newton, MA")
                            Text("All Rights Reserved")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(32)
        .frame(width: 700, height: 600)
    }

    private func section<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            content()
        }
    }

    private func helpItem(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
