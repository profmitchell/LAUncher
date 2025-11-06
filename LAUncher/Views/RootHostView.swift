import SwiftUI
import AppKit

struct RootHostView: View {
    @StateObject private var session = PluginHostSession()
    @Environment(\.colorScheme) private var colorScheme
    @State private var chatWindow: NSWindow?
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TopBarView(session: session)
                PluginCanvasView(session: session)
                StatusBarView(session: session)
            }
            .background(backgroundGradient.ignoresSafeArea())

            if session.isMusicalTypingEnabled {
                MusicalTypingView(session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 960, minHeight: 600)
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

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(.displayP3, red: 0.10, green: 0.10, blue: 0.12, opacity: 1),
                    Color(.displayP3, red: 0.05, green: 0.05, blue: 0.06, opacity: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(.displayP3, red: 0.92, green: 0.93, blue: 0.96, opacity: 1),
                    Color(.displayP3, red: 0.86, green: 0.88, blue: 0.92, opacity: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

