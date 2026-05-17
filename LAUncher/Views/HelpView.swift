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
                            helpItem(title: "Play Notes", description: "Enable QWERTY Piano or connect a MIDI controller to play notes through your plugin.")
                        }
                    }
                    
                    // Features
                    section(title: "Key Features", icon: "star.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpItem(title: "QWERTY Piano", description: "Enable QWERTY Piano to use your QWERTY keyboard as a MIDI controller. The on-screen keyboard can be toggled and repositioned.")
                            helpItem(title: "MIDI Learn", description: "Map MIDI CC controllers to plugin parameters. Click 'MIDI Learn' in the sidebar, then click a parameter and move a MIDI control.")
                            helpItem(title: "BPM Sync", description: "Set the BPM in the left sidebar. When transport is playing, tempo-synced effects (like LFOs) will sync to the host BPM.")
                            helpItem(title: "Themes", description: "Choose from 11 built-in themes or create custom themes. Access from the 'More' menu → 'Theme'.")
                            helpItem(title: "Inspector Panel", description: "Toggle the right-side inspector to access audio device selection and MIDI input settings.")
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
                            helpItem(title: "Draggable Keyboard", description: "Drag the QWERTY Piano keyboard by its handle to reposition it and avoid overlapping plugin UIs.")
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
                            Text("2025 Newton, MA")
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

