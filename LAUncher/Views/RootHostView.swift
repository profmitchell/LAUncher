import SwiftUI
import AppKit

struct RootHostView: View {
    @StateObject private var session = PluginHostSession()
    @Environment(\.colorScheme) private var colorScheme
    @State private var chatWindow: NSWindow?
    @State private var topBarHeight: CGFloat = 84
    @State private var mtOffset: CGSize = .zero
    @State private var leftSidebarWidth: CGFloat = 240
    @State private var rightSidebarWidth: CGFloat = 320
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            LeftSidebarView(session: session)
                .frame(width: leftSidebarWidth)
            
            // Resizable Divider
            ResizableDivider(
                width: $leftSidebarWidth,
                minWidth: 180,
                maxWidth: 400,
                isRightSide: false
            )
            
            // Main Content
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    TopBarView(session: session, expanded: topBarHeight > 96)
                        .frame(height: topBarHeight, alignment: .top)
                        .overlay(
                            ResizableBar(height: $topBarHeight, minHeight: 56, maxHeight: 180)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        )

                    PluginCanvasView(session: session)
                    StatusBarView(session: session)
                }
                .background(backgroundGradient.ignoresSafeArea())

                if session.isMusicalTypingEnabled && session.isMusicalTypingVisible {
                    DraggableMusicalTyping(session: session, offset: $mtOffset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 12)
                }

                RotationGestureCatcherView()
                    .frame(width: 0, height: 0)
            }
            
            // Right Sidebar (Inspector)
            if session.isShowingInspector {
                // Resizable Divider
                ResizableDivider(
                    width: $rightSidebarWidth,
                    minWidth: 200,
                    maxWidth: 500,
                    isRightSide: true
                )
                
                InspectorPanelView(session: session)
                    .frame(width: rightSidebarWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: session.themeManager.currentTheme.id)
        .animation(.easeInOut(duration: 0.3), value: session.isShowingInspector)
        .sheet(isPresented: $session.isShowingPluginPicker) {
            PluginPickerView(session: session)
        }
        .sheet(isPresented: $session.isShowingParameterExport) {
            ParameterExportView(session: session)
        }
        .sheet(isPresented: $session.isShowingMCPTools) {
            MCPToolView(session: session)
        }
        .sheet(isPresented: $session.isShowingMIDIMap) {
            MIDIMapView(session: session)
        }
        .sheet(isPresented: $session.isShowingHelp) {
            HelpView(session: session)
        }
        .onChange(of: session.isShowingChat) {
            Task { @MainActor in
                if session.isShowingChat {
                    if chatWindow == nil || !(chatWindow?.isVisible ?? false) {
                        openChatWindow(session: session)
                    } else {
                        chatWindow?.makeKeyAndOrderFront(nil)
                    }
                } else {
                    chatWindow?.close()
                    chatWindow = nil
                }
            }
        }
    }
    
    private func openChatWindow(session: PluginHostSession) {
        Task { @MainActor in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AI Chat"
            window.center()
            window.isReleasedWhenClosed = false
            
            let hostingView = NSHostingView(rootView: ChatView(session: session, window: window))
            window.contentView = hostingView
            
            window.makeKeyAndOrderFront(nil)
            chatWindow = window
            
            // Track window closure
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    session.isShowingChat = false
                    chatWindow = nil
                }
            }
        }
    }

    // MARK: - Resizable Divider
    private struct ResizableDivider: View {
        @Binding var width: CGFloat
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let isRightSide: Bool // true for right side (drag left), false for left side (drag right)
        
        @State private var isHovering = false
        @State private var startingWidth: CGFloat = 0
        
        var body: some View {
            ZStack {
                Rectangle()
                    .fill(Color.primary.opacity(isHovering ? 0.15 : 0.05))
                    .frame(width: 4)
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
                                let proposed = startingWidth + delta
                                width = min(max(proposed, minWidth), maxWidth)
                            }
                            .onEnded { _ in
                                startingWidth = 0
                            }
                    )
            }
            .frame(width: 4)
        }
    }

    // MARK: - Resize Handle
    private struct ResizableBar: View {
        @Binding var height: CGFloat
        let minHeight: CGFloat
        let maxHeight: CGFloat

        @State private var isHovering = false
        @State private var startingHeight: CGFloat = 0

        var body: some View {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1)
                    .opacity(0.6)
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.25 : 0.15))
                    .frame(width: 64, height: 4)
                    .padding(.vertical, 4)
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startingHeight == 0 { startingHeight = height }
                        let proposed = startingHeight + value.translation.height
                        height = min(max(proposed, minHeight), maxHeight)
                    }
                    .onEnded { _ in
                        startingHeight = 0
                    }
            )
        }
    }

    // MARK: - Draggable Musical Typing Container
    private struct DraggableMusicalTyping: View {
        @ObservedObject var session: PluginHostSession
        @Binding var offset: CGSize
        @State private var dragStart: CGSize = .zero

        var body: some View {
            VStack(spacing: 0) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 80, height: 6)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == .zero { dragStart = offset }
                                offset = CGSize(width: dragStart.width + value.translation.width,
                                                height: dragStart.height + value.translation.height)
                            }
                            .onEnded { _ in dragStart = .zero }
                    )
                MusicalTypingView(session: session)
            }
            .background(Color.clear)
            .offset(offset)
        }
    }

    private var backgroundGradient: LinearGradient {
        let theme = session.themeManager.currentTheme
        return LinearGradient(
            colors: [
                theme.backgroundTop.color,
                theme.backgroundBottom.color
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
