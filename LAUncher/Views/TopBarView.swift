import SwiftUI
import AVFAudio

struct TopBarView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject var themeManager: ThemeManager
    var expanded: Bool = false
    @State private var showIOPopover = false
    
    init(session: PluginHostSession, expanded: Bool = false) {
        self.session = session
        self.themeManager = session.themeManager
        self.expanded = expanded
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, expanded ? 12 : 8)
        }
        .background(themeManager.currentTheme.materialStyle.material)
        .overlay(Rectangle().fill(themeManager.currentTheme.containerBorder.color.opacity(0.5)).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(themeManager.currentTheme.containerBorder.color.opacity(0.5)).frame(height: 1), alignment: .bottom)
        .controlSize(expanded ? .large : .regular)
        .animation(.easeInOut(duration: 0.2), value: themeManager.currentTheme.id)
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
                        inspectorToggleButton
                        helpButton
                    }
                    HStack(spacing: 16) {
                        Spacer()
                        moreMenu
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        titleArea
                        Spacer(minLength: 12)
                        actionButtons
                        inspectorToggleButton
                        helpButton
                        moreMenu
                    }
                }
            }
        }
    }

    private var titleArea: some View {
        HStack(spacing: 8) {
            Text("LAUncher")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("By: Mitchell Cohen")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var inspectorToggleButton: some View {
        Group {
            if session.isShowingInspector {
                Button {
                    session.isShowingInspector.toggle()
                } label: {
                    Image(systemName: "music.note")
                }
                .buttonStyle(.borderedProminent)
                .help("Hide Inspector")
            } else {
                Button {
                    session.isShowingInspector.toggle()
                } label: {
                    Image(systemName: "music.note")
                }
                .buttonStyle(.bordered)
                .help("Show Inspector")
            }
        }
    }

    private var helpButton: some View {
        Button {
            session.isShowingHelp = true
        } label: {
            Label("Help", systemImage: "questionmark.circle")
        }
        .buttonStyle(.bordered)
        .help("Show help and information")
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
            if session.isShowingInspector {
                Button("Hide Inspector", systemImage: "sidebar.right") {
                    session.isShowingInspector = false
                }
            } else {
                Button("Show Inspector", systemImage: "sidebar.right") {
                    session.isShowingInspector = true
                }
            }
            Divider()
            Menu("Theme", systemImage: "paintpalette") {
                ForEach(session.themeManager.availableThemes) { theme in
                    Button {
                        session.themeManager.currentTheme = theme
                    } label: {
                        HStack {
                            Text(theme.name)
                            if session.themeManager.currentTheme.id == theme.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            if session.isMusicalTypingVisible {
                Button("Hide QWERTY Piano", systemImage: "eye.slash") { session.isMusicalTypingVisible = false }
            } else {
                Button("Show QWERTY Piano", systemImage: "eye") { session.isMusicalTypingVisible = true }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .buttonStyle(.bordered)
    }
}
