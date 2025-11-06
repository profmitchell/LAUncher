# LAUncher

A lightweight macOS application for hosting Audio Unit (AU) plugins, supporting both AU 2 and AUv3 formats.

## Features

- **Universal Plugin Support**: Load both AU 2 (traditional) and AUv3 (app extension) plugins
- **MIDI Input**: Connect MIDI devices or use the built-in musical typing keyboard
- **Plugin UI**: Native plugin interface embedded directly in the host window
- **Rescan**: Refresh plugin list to discover newly installed plugins
- **Real-time Audio**: Low-latency audio processing with AVAudioEngine

## Requirements

- macOS 15.7 or later
- Xcode 15.0 or later
- Swift 5.0+

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd LAUncher
```

2. Open the project in Xcode:
```bash
open LAUncher.xcodeproj
```

3. Build and run (⌘R)

## Usage

1. Launch LAUncher
2. Click "Load Plugin…" to browse available plugins
3. Select a plugin from the list
4. Use MIDI input or the musical typing keyboard to play
5. Adjust plugin parameters using the plugin's native UI

## Plugin Locations

LAUncher automatically discovers plugins from:

- `/Library/Audio/Plug-Ins/Components/` (system-wide)
- `~/Library/Audio/Plug-Ins/Components/` (user-specific)

## Rescanning Plugins

After installing new plugins:

1. Click the "Rescan" button in the toolbar
2. Or click "Load Plugin…" and click "Rescan" if needed

## Architecture

- **AudioEngineManager**: Handles AVAudioEngine setup and plugin instantiation
- **PluginHostSession**: Manages plugin state and coordination
- **MidiManager**: MIDI input handling
- **SwiftUI Views**: Modern, responsive UI built with SwiftUI 6

## Supported Plugin Types

- Music Device (Instruments)
- Effects
- Generators
- Mixers
- Panners
- Format Converters
- Offline Effects

## Troubleshooting

### Plugins Not Loading

If you encounter error -3000 or plugins won't load:

1. Ensure the app has been rebuilt after entitlement changes
2. Check that plugins are properly installed in the Components directories
3. Verify plugin compatibility with your macOS version
4. Try validating plugins using: `auval -a`

### Sandbox Restrictions

This app requires sandboxing to be disabled to load third-party plugins. The entitlements file includes:
- `com.apple.security.cs.disable-library-validation`
- `com.apple.security.temporary-exception.audio-unit-host`
- Additional runtime exceptions for plugin compatibility

## Development

### Project Structure

```
LAUncher/
├── LAUncher/
│   ├── App/
│   │   ├── LAUncherApp.swift       # App entry point
│   │   └── ContentView.swift        # Root content view
│   ├── Managers/
│   │   ├── AudioEngineManager.swift    # Audio engine and plugin loading
│   │   ├── PluginHostSession.swift     # Plugin state management
│   │   └── MidiManager.swift           # MIDI input handling
│   ├── Models/
│   │   └── MidiTypes.swift             # MIDI data models
│   ├── Views/
│   │   ├── RootHostView.swift          # Main window view
│   │   ├── PluginPickerView.swift      # Plugin selection UI
│   │   ├── PluginCanvasView.swift      # Plugin UI container
│   │   ├── TopBarView.swift            # Toolbar controls
│   │   ├── StatusBarView.swift         # Status bar display
│   │   └── MusicalTypingView.swift     # On-screen keyboard
│   └── Resources/
│       ├── Assets.xcassets             # App icons and assets
│       └── LAUncher.entitlements       # App entitlements
└── LAUncher.xcodeproj/
```

### Building

1. Select the "LAUncher" scheme
2. Choose your Mac as the destination
3. Build (⌘B) or Run (⌘R)

## License

[Add your license here]

## Credits

Built with SwiftUI and AVFoundation for macOS 15+.

