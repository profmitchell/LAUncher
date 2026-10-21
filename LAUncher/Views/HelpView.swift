import SwiftUI

struct HelpView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
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
                    // Getting Started
                    section(title: "Getting Started", icon: "play.circle.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "Load a Plugin", description: "Click 'Load Plugin…' in the toolbar or left sidebar to browse and load Audio Unit plugins.")
                            helpItem(title: "Start Audio Engine", description: "Use the 'Start Audio' button in the left sidebar to begin audio processing.")
                            helpItem(title: "Play Notes", description: "Enable Musical Typing or connect a MIDI controller to play notes through your plugin.")
                        }
                    }

                    section(title: "Musical Typing (Logic-style)", icon: "keyboard") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "Note keys", description: "A = C of the current octave. Whites: A S D F G H J K L ; '  ·  Blacks: W E T Y U O P")
                            helpItem(title: "Octave", description: "Z = octave down, X = octave up, C = center on Middle C (same as Logic Musical Typing).")
                            helpItem(title: "Sustain", description: "Tab toggles sustain/latch. Notes stay held until sustain is turned off.")
                            helpItem(title: "Velocity", description: "Use the Vel slider, or press , / . to nudge velocity down / up. Typing is ignored while a text field is focused.")
                        }
                    }
                    
                    // Features
                    section(title: "Key Features", icon: "star.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "Musical Typing", description: "Logic Pro–style computer keyboard MIDI. Toggle from the left sidebar or More menu; drag the floating keyboard by its handle.")
                            helpItem(title: "MIDI Learn", description: "Map MIDI CC controllers to plugin parameters. Click 'MIDI Learn' in the sidebar, then click a parameter and move a MIDI control.")
                            helpItem(title: "BPM Sync", description: "Set the BPM in the left sidebar. When transport is playing, tempo-synced effects (like LFOs) will sync to the host BPM.")
                            helpItem(title: "Rescan Plugins", description: "Use Rescan when you install new Audio Units. LAUncher refreshes the AudioComponent registry and updates the browser.")
                            helpItem(title: "Themes", description: "Choose from 11 built-in themes or create custom themes. Access from the 'More' menu → 'Theme'.")
                            helpItem(title: "Settings", description: "Click Settings (or press ⌘,) to choose output/input devices, sample rate, MIDI, and theme. If an effect won’t load, try 48 kHz.")
                        }
                    }
                    
                    // MCP Integration
                    section(title: "MCP (Model Context Protocol)", icon: "wand.and.stars") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "What is MCP?", description: "MCP enables AI-powered workflows for plugin control. The MCP server runs locally and exposes tools for parameter control and patch analysis.")
                            helpItem(title: "Accessing MCP Tools", description: "Use Tools → MCP Tools in the left sidebar, or More → MCP Tools in the top bar. You can open it before loading a plugin to check server status; parameter randomization and similar actions need a loaded plugin.")
                            helpItem(title: "MCP Server", description: "The MCP server runs automatically on port 5555. See MCP-PRD.md for detailed API documentation.")
                        }
                    }
                    
                    // Tips
                    section(title: "Tips & Tricks", icon: "lightbulb.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "Default Plugin", description: "Set a plugin as default in the 'More' menu to auto-load it on launch.")
                            helpItem(title: "Resizable Toolbar", description: "Drag the handle at the bottom of the top toolbar to resize it.")
                            helpItem(title: "Draggable Keyboard", description: "Drag the Musical Typing keyboard by its handle to reposition it and avoid overlapping plugin UIs.")
                            helpItem(title: "Master Gain", description: "Control master output volume using the slider in the bottom status bar.")
                        }
                    }
                    
                    // Credits
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

