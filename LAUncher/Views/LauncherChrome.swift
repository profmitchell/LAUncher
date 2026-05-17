import SwiftUI

enum LauncherChrome {
    static func background(_ theme: AppTheme) -> Color {
        theme.backgroundBottom.color
    }

    static func panel(_ theme: AppTheme) -> Color {
        theme.containerBackground.color.opacity(0.95)
    }

    static func panelSoft(_ theme: AppTheme) -> Color {
        theme.containerBackground.color.opacity(0.62)
    }

    static func textMain(_ theme: AppTheme) -> Color {
        theme.primaryText.color
    }

    static func textMuted(_ theme: AppTheme) -> Color {
        theme.secondaryText.color.opacity(0.9)
    }

    static func border(_ theme: AppTheme) -> Color {
        theme.containerBorder.color.opacity(0.75)
    }

    static func accent(_ theme: AppTheme) -> Color {
        theme.accentColor.color
    }

    static func glassBackground(_ theme: AppTheme, soft: Bool = false) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    soft ? panelSoft(theme) : panel(theme),
                    soft ? panel(theme) : panelSoft(theme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    accent(theme).opacity(0.08),
                    Color.clear,
                    accent(theme).opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct LauncherPanelStyle: ViewModifier {
    let theme: AppTheme
    var cornerRadius: CGFloat = 10
    var shadowRadius: CGFloat = 7
    var shadowY: CGFloat = 3
    var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .background(LauncherChrome.glassBackground(theme, soft: true))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isActive ? LauncherChrome.accent(theme).opacity(0.85) : LauncherChrome.border(theme).opacity(0.45), lineWidth: isActive ? 1.4 : 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: shadowRadius, x: 0, y: shadowY)
    }
}

struct LauncherPillButtonStyle: ButtonStyle {
    let theme: AppTheme
    var iconColor: Color?
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(LauncherChrome.textMain(theme))
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    LauncherChrome.glassBackground(theme, soft: true)
                    if isProminent {
                        LauncherChrome.accent(theme).opacity(configuration.isPressed ? 0.22 : 0.16)
                    } else if configuration.isPressed {
                        Color.white.opacity(0.05)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(LauncherChrome.border(theme).opacity(isProminent ? 0.75 : 0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 4, x: 0, y: 2)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct LauncherToolbarButtonStyle: ButtonStyle {
    let theme: AppTheme
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(LauncherChrome.textMain(theme))
            .frame(minWidth: 56, idealWidth: 64, maxWidth: 74, minHeight: 40, maxHeight: 44)
            .background(
                ZStack {
                    LauncherChrome.glassBackground(theme, soft: true)
                    if isActive {
                        LauncherChrome.accent(theme).opacity(0.18)
                    } else if configuration.isPressed {
                        Color.white.opacity(0.05)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? LauncherChrome.accent(theme).opacity(0.7) : LauncherChrome.border(theme).opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 7, x: 0, y: 4)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

extension View {
    func launcherPanel(theme: AppTheme, cornerRadius: CGFloat = 10, shadowRadius: CGFloat = 7, shadowY: CGFloat = 3, isActive: Bool = false) -> some View {
        modifier(LauncherPanelStyle(theme: theme, cornerRadius: cornerRadius, shadowRadius: shadowRadius, shadowY: shadowY, isActive: isActive))
    }
}
