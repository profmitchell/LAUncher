import SwiftUI

struct PluginCanvasView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject var themeManager: ThemeManager

    init(session: PluginHostSession) {
        self.session = session
        self.themeManager = session.themeManager
    }

    private var theme: AppTheme {
        themeManager.currentTheme
    }

    private var hasPlugin: Bool {
        session.pluginViewController != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = session.lastErrorDescription, session.currentComponent == nil {
                loadErrorBanner(error)
            }

            ZStack {
                if let controller = session.pluginViewController {
                    PluginEditorContainer(viewController: controller, session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            if session.midiMapManager.isInLearnMode {
                                Rectangle()
                                    .stroke(Color.green.opacity(0.55), lineWidth: 2)
                            }
                        }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(hasPlugin ? theme.canvasBackground.color : Color.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: themeManager.currentTheme.id)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(LauncherChrome.textMuted(theme))

            Text("Choose a plugin")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LauncherChrome.textMain(theme))

            Text(
                session.isLibraryVisible
                    ? "Select one from the library, or browse the full list."
                    : "Open the library to pick an instrument or effect."
            )
            .font(.subheadline)
            .foregroundStyle(LauncherChrome.textMuted(theme))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)

            HStack(spacing: 10) {
                if !session.isLibraryVisible {
                    Button {
                        session.isLibraryVisible = true
                    } label: {
                        Label("Show Library", systemImage: "sidebar.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button {
                    session.refreshPluginList()
                    session.isShowingPluginPicker = true
                } label: {
                    Label("Browse Plugins…", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                if let name = session.lastFailedPluginName {
                    Text("Couldn’t load \(name)")
                        .font(.headline)
                } else {
                    Text("Plugin didn’t load")
                        .font(.headline)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Settings") {
                session.openSettings(section: .audio)
            }
            .buttonStyle(.bordered)
            if session.lastFailedPluginName != nil {
                Button("Try Again") {
                    Task { await session.retryLastFailedPlugin() }
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                session.clearLoadError()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.yellow.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.yellow.opacity(0.25))
                .frame(height: 1)
        }
    }
}

private struct PluginEditorContainer: NSViewControllerRepresentable {
    typealias NSViewControllerType = NSViewController

    var viewController: NSViewController
    var session: PluginHostSession

    func makeNSViewController(context: Context) -> NSViewController {
        viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
