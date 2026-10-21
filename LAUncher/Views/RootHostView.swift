import SwiftUI
import AppKit

struct RootHostView: View {
    @StateObject private var session = PluginHostSession()
    @State private var mtOffset: CGSize = CGSize(width: 0, height: -96)

    private var leftSidebarWidth: Binding<CGFloat> {
        Binding(
            get: { session.leftSidebarWidth },
            set: { session.leftSidebarWidth = $0 }
        )
    }

    private var rightSidebarWidth: Binding<CGFloat> {
        Binding(
            get: { session.rightSidebarWidth },
            set: { session.rightSidebarWidth = $0 }
        )
    }

    private var theme: AppTheme {
        session.themeManager.currentTheme
    }

    var body: some View {
        HStack(spacing: 0) {
            if session.isLibraryVisible {
                LeftSidebarView(session: session)
                    .frame(width: session.leftSidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                ResizableDivider(
                    width: leftSidebarWidth,
                    minWidth: 220,
                    maxWidth: 380,
                    isRightSide: false
                )
            }

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    TopBarView(session: session)
                    PluginCanvasView(session: session)
                    StatusBarView(session: session)
                }
                .background(theme.backgroundBottom.color.ignoresSafeArea())

                if session.isMusicalTypingEnabled && session.isMusicalTypingVisible {
                    DraggableQWERTYPiano(session: session, offset: $mtOffset)
                        .padding(.trailing, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                RotationGestureCatcherView()
                    .frame(width: 0, height: 0)
            }

            if session.isShowingInspector {
                ResizableDivider(
                    width: rightSidebarWidth,
                    minWidth: 280,
                    maxWidth: 520,
                    isRightSide: true
                )

                InspectorPanelView(session: session)
                    .frame(width: session.rightSidebarWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .animation(.easeInOut(duration: 0.22), value: session.isLibraryVisible)
        .animation(.easeInOut(duration: 0.22), value: session.isShowingInspector)
        .animation(.easeInOut(duration: 0.2), value: session.themeManager.currentTheme.id)
        .sheet(isPresented: $session.isShowingPluginPicker) {
            PluginPickerView(session: session)
        }
        .sheet(isPresented: $session.isShowingParameterExport) {
            ParameterExportView(session: session)
        }
        .sheet(isPresented: $session.isShowingMIDIMap) {
            MIDIMapView(session: session)
        }
        .sheet(isPresented: $session.isShowingHelp) {
            HelpView(session: session)
        }
        .sheet(isPresented: $session.isShowingSettings) {
            SettingsView(session: session)
        }
        .background {
            Button("") { session.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }

    private struct ResizableDivider: View {
        @Binding var width: CGFloat
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let isRightSide: Bool

        @State private var isHovering = false
        @State private var startingWidth: CGFloat = 0

        var body: some View {
            Rectangle()
                .fill(Color.primary.opacity(isHovering ? 0.18 : 0.06))
                .frame(width: 3)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if startingWidth == 0 { startingWidth = width }
                            let delta = isRightSide ? -value.translation.width : value.translation.width
                            width = min(max(startingWidth + delta, minWidth), maxWidth)
                        }
                        .onEnded { _ in
                            startingWidth = 0
                        }
                )
                .frame(width: 3)
        }
    }

    private struct DraggableQWERTYPiano: View {
        @ObservedObject var session: PluginHostSession
        @Binding var offset: CGSize
        @State private var dragStart: CGSize = .zero

        private var theme: AppTheme { session.themeManager.currentTheme }

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LauncherChrome.textMuted(theme))
                    Text("QWERTY Piano")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LauncherChrome.textMain(theme))
                    Spacer(minLength: 0)
                    Button {
                        session.isMusicalTypingVisible = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(LauncherChrome.textMuted(theme))
                    .help("Hide QWERTY Piano")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragStart == .zero { dragStart = offset }
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStart = .zero
                        }
                )

                Divider().opacity(0.35)

                MusicalTypingView(session: session)
            }
            .frame(minWidth: 480)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(LauncherChrome.border(theme).opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
            .offset(offset)
        }
    }
}
