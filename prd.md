[PRODUCT SPEC] Minimal AU Instrument Host (SwiftUI 6, macOS 15)

================================================================
1. PRODUCT VISION
================================================================
- Deliver a lightweight macOS 15 app whose only job is to open a single Audio Unit instrument and present the plugin’s own editor.
- Provide dependable audio output and MIDI input so the loaded instrument is immediately playable.
- Keep host chrome minimal: no deep parameter browsers, no racks, no sequencing features.

================================================================
2. CORE SCOPE (WHAT MUST SHIP)
================================================================
- Launch template SwiftUI 6 app with a single window.
- Allow the user to pick any installed AU instrument and load it into the audio engine.
- Embed the plugin’s native Cocoa editor view in the center of the window.
- Route MIDI from one selected hardware device and an optional QWERTY keyboard overlay to the instrument.
- Handle audio engine lifecycle (start/stop) and surface simple status feedback (running/error).

================================================================
3. PRIMARY USER FLOW
================================================================
1. User opens the app; the window shows an empty host canvas.
2. User clicks “Load Instrument…” and selects an AU instrument from the system picker.
3. Host instantiates the AU, connects it to AVAudioEngine, and starts the engine if needed.
4. The plugin’s UI appears centered in the window; the user plays via MIDI or QWERTY.
5. User can stop the engine or unload the plugin from the top bar, then load another instrument if desired.

================================================================
4. ARCHITECTURE OVERVIEW
================================================================

4.1 AudioEngineManager
- Owns the AVAudioEngine instance.
- Loads exactly one AVAudioUnit instrument at a time (AudioComponentDescription type = instrument).
- Connects instrument → mainMixerNode → outputNode and manages engine start/stop.
- Exposes light telemetry (sample rate, buffer size, running/error state) for UI display.

4.2 PluginHostSession (ObservableObject)
- Central observable state model shared with SwiftUI views.
- Tracks the currently loaded plugin (name, manufacturer, component description, AVAudioUnit/AUAudioUnit references).
- Publishes engine status, last error, and whether QWERTY input is enabled.
- Mediates interactions between the UI, AudioEngineManager, and MidiManager.

4.3 MidiManager
- Discovers CoreMIDI sources on launch and maintains the selected device.
- Provides a uniform MidiEvent stream (note on/off, CC) to the host session.
- Sends events to the loaded instrument via AVAudioUnitMIDIInstrument / AUAudioUnit MIDI API.
- Optionally injects events from the musical typing overlay.

4.4 SwiftUI Shell
- RootHostView: assembles the layout (top bar + plugin canvas + status strip).
- PluginCanvasView: wraps the plugin editor NSViewController via NSViewControllerRepresentable.
- TopBarView: houses “Load Instrument…”, engine state indicator, MIDI device dropdown, QWERTY toggle, and unload button.
- StatusBarView: lightweight line showing sample rate / buffer size / current MIDI source / error banner.

================================================================
5. UI GUIDELINES
================================================================
- Visual language: neutral dark canvas so the plugin UI reads as the focal point.
- Plugin canvas: centered, padded, auto-resizes with window; show a bordered placeholder while nothing is loaded.
- Top bar: slim, Mac-style toolbar visuals; avoid verbose metadata—show plugin name and basic controls only.
- MIDI/QWERTY feedback: small indicators (LED dots or labels) to reassure users that input is active.
- Errors: present inline banner if AU fails to load or engine stops unexpectedly.

================================================================
6. NON-GOALS (v1)
================================================================
- No parameter tree browsers, macro panels, or generic sliders; all control happens inside the plugin UI.
- No MIDI learn, CC mapping editors, or automation layers.
- No audio effects chain, recording, metering, or multi-plugin support.
- No preset management beyond what the plugin itself supplies.

================================================================
7. FUTURE CONSIDERATIONS (PARKING LOT)
================================================================
- Persist preferred MIDI device selection and window layout.
- Add lightweight metering or CPU usage indicators if users request them.
- Explore optional macro panels or MIDI mapping after the core hosting experience proves solid.
- Provide a basic recent-plugin menu or favorites list for faster relaunch.
