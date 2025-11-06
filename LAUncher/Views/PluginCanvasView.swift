import SwiftUI

struct PluginCanvasView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    init(session: PluginHostSession) {
        self.session = session
        self.themeManager = session.themeManager
    }
    
    private var theme: AppTheme {
        themeManager.currentTheme
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(placeholderFill)
                .opacity(session.pluginViewController == nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: session.pluginViewController == nil)

            if let controller = session.pluginViewController {
                PluginEditorContainer(viewController: controller, session: session)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(12)
                    .background(controllerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        // Visual indicator when learn mode is active
                        Group {
                            if session.midiMapManager.isInLearnMode {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.green.opacity(0.6), lineWidth: 3)
                                    .padding(12)
                            }
                        }
                    )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("Load an Audio Unit plugin to begin")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(containerBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .padding(16)
        )
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.2), value: themeManager.currentTheme.id)
    }

    private var placeholderFill: Color {
        theme.placeholderFill.color
    }

    private var containerBackground: Color {
        theme.containerBackground.color
    }

    private var borderColor: Color {
        theme.containerBorder.color
    }

    private var controllerBackground: Color {
        theme.canvasBackground.color
    }
}

private struct PluginEditorContainer: NSViewControllerRepresentable {
    typealias NSViewControllerType = NSViewController

    var viewController: NSViewController
    var session: PluginHostSession

    func makeNSViewController(context: Context) -> NSViewController {
        return viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        // Don't force layout here - it causes recursion warnings
        // Plugin view controllers handle their own updates when parameters change
    }
}
