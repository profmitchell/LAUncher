import SwiftUI
import AppKit

struct AppTheme: Identifiable, Codable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    
    // Background colors
    let backgroundTop: ThemeColor
    let backgroundBottom: ThemeColor
    
    // Container colors
    let containerBackground: ThemeColor
    let containerBorder: ThemeColor
    
    // Text colors
    let primaryText: ThemeColor
    let secondaryText: ThemeColor
    
    // Accent colors
    let accentColor: ThemeColor
    
    // Plugin canvas colors
    let canvasBackground: ThemeColor
    let canvasBorder: ThemeColor
    let placeholderFill: ThemeColor
    
    // Material styles
    let materialStyle: MaterialStyle
    
    enum MaterialStyle: String, Codable {
        case ultraThin
        case thin
        case regular
        case thick
        case ultraThick
        
        var material: Material {
            switch self {
            case .ultraThin: return .ultraThinMaterial
            case .thin: return .thinMaterial
            case .regular: return .regularMaterial
            case .thick: return .thickMaterial
            case .ultraThick: return .ultraThickMaterial
            }
        }
    }
    
    struct ThemeColor: Codable {
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double
        
        var color: Color {
            Color(.displayP3, red: red, green: green, blue: blue, opacity: opacity)
        }
        
        init(_ color: Color) {
            // Convert SwiftUI Color to NSColor for component extraction
            let nsColor = NSColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if let rgbColor = nsColor.usingColorSpace(.displayP3) {
                rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            } else {
                // Fallback for colorspace conversion issues
                nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            }
            self.red = Double(r)
            self.green = Double(g)
            self.blue = Double(b)
            self.opacity = Double(a)
        }
        
        init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
            self.red = red
            self.green = green
            self.blue = blue
            self.opacity = opacity
        }
    }
    
    // Built-in themes
    static let dark = AppTheme(
        id: "dark",
        name: "Dark",
        isBuiltIn: true,
        backgroundTop: ThemeColor(red: 0.10, green: 0.10, blue: 0.12, opacity: 1.0),
        backgroundBottom: ThemeColor(red: 0.05, green: 0.05, blue: 0.06, opacity: 1.0),
        containerBackground: ThemeColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.02),
        containerBorder: ThemeColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.05),
        primaryText: ThemeColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0),
        secondaryText: ThemeColor(red: 0.7, green: 0.7, blue: 0.7, opacity: 1.0),
        accentColor: ThemeColor(red: 0.0, green: 0.5, blue: 1.0, opacity: 1.0),
        canvasBackground: ThemeColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.4),
        canvasBorder: ThemeColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.05),
        placeholderFill: ThemeColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.06),
        materialStyle: .ultraThin
    )
    
    static let light = AppTheme(
        id: "light",
        name: "Light",
        isBuiltIn: true,
        backgroundTop: ThemeColor(red: 0.92, green: 0.93, blue: 0.96, opacity: 1.0),
        backgroundBottom: ThemeColor(red: 0.86, green: 0.88, blue: 0.92, opacity: 1.0),
        containerBackground: ThemeColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.6),
        containerBorder: ThemeColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.08),
        primaryText: ThemeColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0),
        secondaryText: ThemeColor(red: 0.3, green: 0.3, blue: 0.3, opacity: 1.0),
        accentColor: ThemeColor(red: 0.0, green: 0.4, blue: 0.8, opacity: 1.0),
        canvasBackground: ThemeColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0),
        canvasBorder: ThemeColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.08),
        placeholderFill: ThemeColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.05),
        materialStyle: .ultraThin
    )
    
    static let midnight = AppTheme(
        id: "midnight",
        name: "Midnight",
        isBuiltIn: true,
        backgroundTop: ThemeColor(red: 0.05, green: 0.05, blue: 0.08, opacity: 1.0),
        backgroundBottom: ThemeColor(red: 0.02, green: 0.02, blue: 0.04, opacity: 1.0),
        containerBackground: ThemeColor(red: 0.1, green: 0.1, blue: 0.12, opacity: 0.5),
        containerBorder: ThemeColor(red: 0.2, green: 0.2, blue: 0.25, opacity: 0.3),
        primaryText: ThemeColor(red: 0.95, green: 0.95, blue: 0.98, opacity: 1.0),
        secondaryText: ThemeColor(red: 0.6, green: 0.6, blue: 0.65, opacity: 1.0),
        accentColor: ThemeColor(red: 0.4, green: 0.5, blue: 1.0, opacity: 1.0),
        canvasBackground: ThemeColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.5),
        canvasBorder: ThemeColor(red: 0.2, green: 0.2, blue: 0.25, opacity: 0.3),
        placeholderFill: ThemeColor(red: 0.1, green: 0.1, blue: 0.12, opacity: 0.3),
        materialStyle: .ultraThin
    )
    
    static let sunset = AppTheme(
        id: "sunset",
        name: "Sunset",
        isBuiltIn: true,
        backgroundTop: ThemeColor(red: 0.25, green: 0.15, blue: 0.2, opacity: 1.0),
        backgroundBottom: ThemeColor(red: 0.15, green: 0.08, blue: 0.12, opacity: 1.0),
        containerBackground: ThemeColor(red: 0.3, green: 0.2, blue: 0.25, opacity: 0.4),
        containerBorder: ThemeColor(red: 0.5, green: 0.3, blue: 0.4, opacity: 0.2),
        primaryText: ThemeColor(red: 1.0, green: 0.9, blue: 0.85, opacity: 1.0),
        secondaryText: ThemeColor(red: 0.8, green: 0.6, blue: 0.65, opacity: 1.0),
        accentColor: ThemeColor(red: 1.0, green: 0.5, blue: 0.3, opacity: 1.0),
        canvasBackground: ThemeColor(red: 0.2, green: 0.12, blue: 0.15, opacity: 0.6),
        canvasBorder: ThemeColor(red: 0.5, green: 0.3, blue: 0.4, opacity: 0.2),
        placeholderFill: ThemeColor(red: 0.4, green: 0.25, blue: 0.3, opacity: 0.2),
        materialStyle: .ultraThin
    )
    
    static let ocean = AppTheme(
        id: "ocean",
        name: "Ocean",
        isBuiltIn: true,
        backgroundTop: ThemeColor(red: 0.1, green: 0.15, blue: 0.22, opacity: 1.0),
        backgroundBottom: ThemeColor(red: 0.05, green: 0.08, blue: 0.12, opacity: 1.0),
        containerBackground: ThemeColor(red: 0.15, green: 0.2, blue: 0.28, opacity: 0.4),
        containerBorder: ThemeColor(red: 0.2, green: 0.3, blue: 0.4, opacity: 0.3),
        primaryText: ThemeColor(red: 0.85, green: 0.95, blue: 1.0, opacity: 1.0),
        secondaryText: ThemeColor(red: 0.6, green: 0.7, blue: 0.8, opacity: 1.0),
        accentColor: ThemeColor(red: 0.2, green: 0.6, blue: 1.0, opacity: 1.0),
        canvasBackground: ThemeColor(red: 0.08, green: 0.12, blue: 0.18, opacity: 0.6),
        canvasBorder: ThemeColor(red: 0.2, green: 0.3, blue: 0.4, opacity: 0.3),
        placeholderFill: ThemeColor(red: 0.15, green: 0.2, blue: 0.28, opacity: 0.3),
        materialStyle: .ultraThin
    )
    
    static var builtInThemes: [AppTheme] {
        [.dark, .light, .midnight, .sunset, .ocean]
    }
}

