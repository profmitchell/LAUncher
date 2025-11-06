import Foundation
import SwiftUI
import Combine

@MainActor
final class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme {
        didSet {
            saveCurrentTheme()
        }
    }
    
    @Published var availableThemes: [AppTheme] = []
    
    private let defaults = UserDefaults.standard
    private let currentThemeKey = "CurrentThemeID"
    private let customThemesKey = "CustomThemes"
    
    init() {
        // Load built-in themes
        var themes = AppTheme.builtInThemes
        
        // Load custom themes
        if let customThemesData = defaults.data(forKey: customThemesKey),
           let customThemes = try? JSONDecoder().decode([AppTheme].self, from: customThemesData) {
            themes.append(contentsOf: customThemes)
        }
        
        availableThemes = themes
        
        // Load current theme
        if let themeID = defaults.string(forKey: currentThemeKey),
           let theme = themes.first(where: { $0.id == themeID }) {
            currentTheme = theme
        } else {
            // Default to system appearance
            currentTheme = AppTheme.dark
        }
    }
    
    private func saveCurrentTheme() {
        defaults.set(currentTheme.id, forKey: currentThemeKey)
    }
    
    func addCustomTheme(_ theme: AppTheme) {
        var customThemes = loadCustomThemes()
        customThemes.append(theme)
        saveCustomThemes(customThemes)
        availableThemes.append(theme)
    }
    
    func removeCustomTheme(_ theme: AppTheme) {
        guard !theme.isBuiltIn else { return }
        
        var customThemes = loadCustomThemes()
        customThemes.removeAll { $0.id == theme.id }
        saveCustomThemes(customThemes)
        
        availableThemes.removeAll { $0.id == theme.id }
        
        if currentTheme.id == theme.id {
            currentTheme = AppTheme.dark
        }
    }
    
    func updateCustomTheme(_ theme: AppTheme) {
        guard !theme.isBuiltIn else { return }
        
        var customThemes = loadCustomThemes()
        if let index = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[index] = theme
        } else {
            customThemes.append(theme)
        }
        saveCustomThemes(customThemes)
        
        if let index = availableThemes.firstIndex(where: { $0.id == theme.id }) {
            availableThemes[index] = theme
        } else {
            availableThemes.append(theme)
        }
        
        if currentTheme.id == theme.id {
            currentTheme = theme
        }
    }
    
    private func loadCustomThemes() -> [AppTheme] {
        guard let data = defaults.data(forKey: customThemesKey),
              let themes = try? JSONDecoder().decode([AppTheme].self, from: data) else {
            return []
        }
        return themes
    }
    
    private func saveCustomThemes(_ themes: [AppTheme]) {
        if let data = try? JSONEncoder().encode(themes) {
            defaults.set(data, forKey: customThemesKey)
        }
    }
}

