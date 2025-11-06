import Foundation
import Combine
import AVFoundation
import AudioToolbox
import AudioUnit
import AppKit
import CoreAudioKit

@MainActor
final class PluginHostSession: ObservableObject {
    enum EngineState: Equatable {
        case stopped
        case running
        case error(String)
    }

    @Published private(set) var engineState: EngineState = .stopped
    @Published private(set) var currentComponent: AVAudioUnitComponent?
    @Published private(set) var pluginViewController: NSViewController?
    @Published private(set) var availableInstruments: [AVAudioUnitComponent] = []
    @Published private(set) var availablePlugins: [AVAudioUnitComponent] = []
    @Published private(set) var lastErrorDescription: String?
    @Published private(set) var sampleRate: Double = 0
    @Published private(set) var bufferDuration: TimeInterval = 0
    @Published var bpm: Double = 120 {
        didSet { engineManager.setTempo(bpm) }
    }
    @Published var isTransportPlaying: Bool = true {
        didSet { engineManager.setTransportPlaying(isTransportPlaying) }
    }
    @Published private(set) var lastMidiEvent: MidiEvent?

    @Published var isShowingPluginPicker = false
    @Published var isMusicalTypingEnabled = false
    @Published var isMusicalTypingVisible = true
    @Published var isShowingParameterExport = false
    @Published var isShowingMCPTools = false
    @Published var isShowingMIDIMap = false
    @Published var isShowingChat = false
    @Published var isShowingInspector = false
    @Published var exportedParameterJSON: String = ""
    
    // Parameter analysis cache
    @Published private(set) var analyzedParameters: ParameterAnalysis?
    
    struct ParameterAnalysis {
        var oscillatorLevelIds: [String] = []
        var filterCutoffIds: [String] = []
        var modulationMatrixSlots: [(source: AUParameter?, dest: AUParameter?, amount: AUParameter?)] = []
        var pluginName: String
        var pluginType: String // "Vital", "Serum", etc.
    }
    @Published var selectedMidiSource: MidiSource? {
        didSet {
            if midiManager.selectedSource != selectedMidiSource {
                midiManager.selectedSource = selectedMidiSource
            }
        }
    }

    var midiSources: [MidiSource] {
        midiManager.availableSources
    }

    let engineManager = AudioEngineManager()
    let midiManager = MidiManager()
    let audioDeviceManager = AudioDeviceManager()
    let midiMapManager = MIDIMapManager()
    let musicalTypingManager = MusicalTypingManager()
    let themeManager = ThemeManager()
    private var cancellables: Set<AnyCancellable> = []
    private var mcpServer: MCPServerManager?
    private var parameterChangeMonitor: Task<Void, Never>?
    private var lastParameterValues: [String: AUValue] = [:]
    private var isMonitoringParameterChanges = false
    private var isSettingParameterProgrammatically = false

    init() {
        observeEngine()
        observeMidi()
        refreshInstrumentList()
        refreshPluginList()
        refreshMetrics()
        audioDeviceManager.refreshDevices()
        
        // Set default devices
        if selectedInputDevice == nil {
            selectedInputDevice = audioDeviceManager.inputDevices.first
        }
        if selectedOutputDevice == nil {
            selectedOutputDevice = audioDeviceManager.outputDevices.first
        }
        
        // Start MCP HTTP server on port 5555 (on background thread to avoid blocking UI)
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await MainActor.run {
                guard self.mcpServer == nil else {
                    print("⚠️ MCP server already exists")
                    return
                }
                let server = MCPServerManager(session: self)
                self.mcpServer = server
                try? server.start()
            }
        }
        // Wire musical typing to send virtual notes
        musicalTypingManager.sendNoteOn = { [weak self] note, velocity in
            Task { @MainActor in self?.sendVirtualNoteOn(noteNumber: note, velocity: velocity) }
        }
        musicalTypingManager.sendNoteOff = { [weak self] note in
            Task { @MainActor in self?.sendVirtualNoteOff(noteNumber: note) }
        }

        // Attempt to auto-load default plugin after a short delay to ensure lists populated
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self.loadDefaultPluginIfAvailable()
        }

        // Initialize engine tempo and transport
        engineManager.setTempo(bpm)
        engineManager.setTransportPlaying(isTransportPlaying)
    }

    // MARK: - Master Gain
    @Published var masterGain: Float = 0.8 {
        didSet { engineManager.setMasterGain(masterGain) }
    }

    @Published var selectedInputDevice: AudioDevice? {
        didSet {
            if selectedInputDevice != oldValue {
                try? engineManager.setInputDevice(selectedInputDevice)
            }
        }
    }
    
    @Published var selectedOutputDevice: AudioDevice? {
        didSet {
            if selectedOutputDevice != oldValue {
                Task { try? engineManager.setOutputDevice(selectedOutputDevice) }
            }
        }
    }
    
    var inputDevices: [AudioDevice] {
        audioDeviceManager.inputDevices
    }
    
    var outputDevices: [AudioDevice] {
        audioDeviceManager.outputDevices
    }

    func refreshInstrumentList() {
        let instrumentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let manager = AVAudioUnitComponentManager.shared()
        let components = manager.components(matching: instrumentDescription)

        availableInstruments = components.sorted(by: { (lhs: AVAudioUnitComponent, rhs: AVAudioUnitComponent) -> Bool in
            let leftName = lhs.name
            let rightName = rhs.name
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        })
    }

    func refreshPluginList() {
        print("🔄 Rescanning plugins...")
        let manager = AVAudioUnitComponentManager.shared()
        var allComponents: [AVAudioUnitComponent] = []
        
        // Search for all AU types (both AU 2 and AUv3)
        let types: [OSType] = [
            kAudioUnitType_MusicDevice,
            kAudioUnitType_Effect,
            kAudioUnitType_Generator,
            kAudioUnitType_Mixer,
            kAudioUnitType_Panner,
            kAudioUnitType_FormatConverter,
            kAudioUnitType_OfflineEffect
        ]
        
        for type in types {
            let description = AudioComponentDescription(
                componentType: type,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            let components = manager.components(matching: description)
            allComponents.append(contentsOf: components)
            
            // Debug logging
            if !components.isEmpty {
                print("Found \(components.count) plugins of type \(typeToString(type))")
                for component in components.prefix(3) {
                    // componentURL is deprecated, so we can't reliably detect AU 2 vs AUv3
                    // Both types are discovered by AVAudioUnitComponentManager
                    print("  - \(component.name) by \(component.manufacturerName)")
                }
            }
        }
        
        // Remove duplicates and sort
        var seenIDs = Set<String>()
        availablePlugins = allComponents
            .filter { component in
                let desc = component.audioComponentDescription
                let id = "\(desc.componentType)-\(desc.componentSubType)-\(desc.componentManufacturer)"
                if seenIDs.contains(id) {
                    return false
                }
                seenIDs.insert(id)
                return true
            }
            .sorted(by: { (lhs: AVAudioUnitComponent, rhs: AVAudioUnitComponent) -> Bool in
                let leftName = lhs.name
                let rightName = rhs.name
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            })
        
        print("✅ Total unique plugins found: \(availablePlugins.count)")
    }
    
    func rescanPlugins() {
        refreshInstrumentList()
        refreshPluginList()
    }
    
    private func typeToString(_ type: OSType) -> String {
        switch type {
        case kAudioUnitType_MusicDevice: return "MusicDevice (Instrument)"
        case kAudioUnitType_Effect: return "Effect"
        case kAudioUnitType_Generator: return "Generator"
        case kAudioUnitType_Mixer: return "Mixer"
        case kAudioUnitType_Panner: return "Panner"
        case kAudioUnitType_FormatConverter: return "FormatConverter"
        case kAudioUnitType_OfflineEffect: return "OfflineEffect"
        default: return "Unknown(\(type))"
        }
    }

    func load(component: AVAudioUnitComponent) async {
        do {
            pluginViewController = nil
            lastErrorDescription = nil
            
            // Debug: Log component details before loading
            let desc = component.audioComponentDescription
            print("🔍 Attempting to load plugin: '\(component.name)'")
            print("   Type: \(desc.componentType) (\(fourCCToString(desc.componentType)))")
            print("   SubType: \(desc.componentSubType) (\(fourCCToString(desc.componentSubType)))")
            print("   Manufacturer: \(desc.componentManufacturer) (\(fourCCToString(desc.componentManufacturer)))")
            print("   TypeName: \(component.typeName)")
            
            // Try to load the plugin - for AUv3 plugins, we might need to try different approaches
            let node = try await engineManager.loadPlugin(componentDescription: desc, component: component)
            currentComponent = component
            refreshMetrics()
            
            print("✅ Successfully loaded plugin '\(component.name)'")
            
            // Try to load the view controller (this may fail for plugins without UI, which is OK)
            do {
                try await loadPluginViewController(from: node.auAudioUnit)
            } catch {
                // Log the error but don't fail the entire load if UI isn't available
                print("Warning: Could not load plugin UI: \(error.localizedDescription)")
            }
            
            engineState = .running
            
            // Analyze parameters after successful load
            Task {
                await analyzeParameters()
            }
            
            // Start parameter change monitoring for learn mode
            startParameterChangeMonitoring()
        } catch {
            engineManager.unloadPlugin()
            currentComponent = nil
            pluginViewController = nil
            let errorMessage = error.localizedDescription
            lastErrorDescription = errorMessage
            engineState = .error(errorMessage)
            
            // Log detailed error for debugging
            let nsError = error as NSError
            let desc = component.audioComponentDescription
            print("❌ Failed to load plugin '\(component.name)' by \(component.manufacturerName)")
            print("   Component Description: type=\(desc.componentType), subtype=\(desc.componentSubType), manufacturer=\(desc.componentManufacturer)")
            print("   Error domain: \(nsError.domain), code: \(nsError.code)")
            print("   Error message: \(errorMessage)")
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] {
                print("   Underlying error: \(underlyingError)")
            }
        }
    }
    
    private func fourCCToString(_ value: OSType) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "???"
    }

    func unloadCurrentInstrument() {
        engineManager.unloadPlugin()
        currentComponent = nil
        pluginViewController = nil
        analyzedParameters = nil
        parameterChangeMonitor?.cancel()
        parameterChangeMonitor = nil
        isMonitoringParameterChanges = false
        lastParameterValues.removeAll()
        engineState = .stopped
    }

    // MARK: - Default Plugin Persistence
    private let defaults = UserDefaults.standard
    private let defaultTypeKey = "DefaultPluginType"
    private let defaultSubTypeKey = "DefaultPluginSubType"
    private let defaultManuKey = "DefaultPluginManufacturer"
    private let defaultNameKey = "DefaultPluginName"

    func setDefaultPlugin(_ component: AVAudioUnitComponent) {
        let desc = component.audioComponentDescription
        defaults.set(Int(desc.componentType), forKey: defaultTypeKey)
        defaults.set(Int(desc.componentSubType), forKey: defaultSubTypeKey)
        defaults.set(Int(desc.componentManufacturer), forKey: defaultManuKey)
        defaults.set(component.name, forKey: defaultNameKey)
    }

    func clearDefaultPlugin() {
        defaults.removeObject(forKey: defaultTypeKey)
        defaults.removeObject(forKey: defaultSubTypeKey)
        defaults.removeObject(forKey: defaultManuKey)
        defaults.removeObject(forKey: defaultNameKey)
    }

    func loadDefaultPluginIfAvailable() async {
        let type = defaults.integer(forKey: defaultTypeKey)
        let sub = defaults.integer(forKey: defaultSubTypeKey)
        let manu = defaults.integer(forKey: defaultManuKey)
        guard type != 0 || sub != 0 || manu != 0 else { return }

        let target = AudioComponentDescription(
            componentType: OSType(type),
            componentSubType: OSType(sub),
            componentManufacturer: OSType(manu),
            componentFlags: 0,
            componentFlagsMask: 0
        )

        if let matched = availablePlugins.first(where: { comp in
            let d = comp.audioComponentDescription
            return d.componentType == target.componentType &&
                   d.componentSubType == target.componentSubType &&
                   d.componentManufacturer == target.componentManufacturer
        }) {
            await load(component: matched)
        }
    }

    func toggleTransport() {
        isTransportPlaying.toggle()
    }

    func toggleEngineRunning() {
        if engineManager.isRunning {
            engineManager.stopEngine()
        } else {
            try? engineManager.startEngine()
        }
    }

    func handleMidi(event: MidiEvent) {
        lastMidiEvent = event
        engineManager.send(midiEvent: event)
    }

    func sendVirtualNoteOn(noteNumber: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        let status: UInt8 = 0x90 | (channel & 0x0F)
        let event = MidiEvent(timestamp: 0, source: nil, statusByte: status, data1: noteNumber, data2: velocity)
        handleMidi(event: event)
    }

    func sendVirtualNoteOff(noteNumber: UInt8, channel: UInt8 = 0) {
        let status: UInt8 = 0x80 | (channel & 0x0F)
        let event = MidiEvent(timestamp: 0, source: nil, statusByte: status, data1: noteNumber, data2: 0)
        handleMidi(event: event)
    }

    private func observeEngine() {
        engineManager.$isRunning
            .sink { [weak self] isRunning in
                guard let self else { return }
                self.engineState = isRunning ? .running : .stopped
            }
            .store(in: &cancellables)

        engineManager.$lastError
            .sink { [weak self] error in
                guard let self else { return }
                if let error {
                    self.engineState = .error(error.localizedDescription)
                    self.lastErrorDescription = error.localizedDescription
                }
            }
            .store(in: &cancellables)
    }

    private func observeMidi() {
        midiManager.eventHandler = { [weak self] event in
            guard let self else { return }
            
            // Handle MIDI CC mappings
            let status = event.statusByte
            let ccStatus: UInt8 = 0xB0
            
            if (status & 0xF0) == ccStatus {
                let ccNumber = event.data1
                let ccValue = event.data2
                
                // Check if we're learning
                if midiMapManager.isLearning, let paramId = midiMapManager.learningParameterId {
                    // Create new mapping
                    if let param = self.findParameter(identifier: paramId) {
                        let mapping = MIDIMapping(
                            parameterId: paramId,
                            parameterDisplayName: param.displayName,
                            ccNumber: ccNumber,
                            minValue: param.minValue,
                            maxValue: param.maxValue
                        )
                        midiMapManager.mappings.append(mapping)
                        midiMapManager.isLearning = false
                        midiMapManager.learningParameterId = nil
                        midiMapManager.lastCCReceived = ccNumber
                        return // Handled
                    }
                }
                
                // Apply existing mappings - support multiple parameters per CC
                let mappingsForCC = midiMapManager.mappings.filter { $0.ccNumber == ccNumber }
                isSettingParameterProgrammatically = true
                defer { isSettingParameterProgrammatically = false }
                
                for mapping in mappingsForCC {
                    if let param = self.findParameter(identifier: mapping.parameterId) {
                        // Convert MIDI CC (0-127) to parameter value
                        let normalizedValue = Float(ccValue) / 127.0
                        let paramValue = mapping.minValue + (normalizedValue * (mapping.maxValue - mapping.minValue))
                        
                        // Set parameter value
                        let clampedValue = max(param.minValue, min(param.maxValue, AUValue(paramValue)))
                        param.setValue(clampedValue, originator: nil)
                    }
                }
                
                if !mappingsForCC.isEmpty {
                    return // Handled
                }
            }
            
            // Handle regular MIDI events (notes, etc.)
            self.handleMidi(event: event)
        }

        midiManager.$availableSources
            .sink { [weak self] _ in
                guard let self else { return }
                if self.selectedMidiSource == nil {
                    self.selectedMidiSource = self.midiManager.selectedSource
                }
            }
            .store(in: &cancellables)

        midiManager.$selectedSource
            .sink { [weak self] source in
                guard let self else { return }
                if self.selectedMidiSource != source {
                    self.selectedMidiSource = source
                }
            }
            .store(in: &cancellables)
    }

    private func refreshMetrics() {
        sampleRate = engineManager.sampleRate
        bufferDuration = engineManager.bufferDuration
    }

    func exportParametersAsJSON() {
        guard let audioUnit = engineManager.auAudioUnit else {
            exportedParameterJSON = "{\n  \"error\": \"No plugin loaded\"\n}"
            isShowingParameterExport = true
            return
        }
        
        var jsonDict: [String: Any] = [:]
        
        // Plugin info
        if let component = currentComponent {
            jsonDict["plugin"] = [
                "name": component.name,
                "manufacturer": component.manufacturerName,
                "type": component.typeName
            ]
            
            let desc = component.audioComponentDescription
            jsonDict["componentDescription"] = [
                "type": "\(fourCCToString(desc.componentType)) (\(desc.componentType))",
                "subtype": "\(fourCCToString(desc.componentSubType)) (\(desc.componentSubType))",
                "manufacturer": "\(fourCCToString(desc.componentManufacturer)) (\(desc.componentManufacturer))"
            ]
        }
        
        // Audio unit info
        let outputFormat = audioUnit.outputBusses[0].format
        jsonDict["audioUnit"] = [
            "sampleRate": outputFormat.sampleRate,
            "channelCount": outputFormat.channelCount,
            "canProcessInPlace": audioUnit.canProcessInPlace,
            "hasMIDIInput": audioUnit.scheduleMIDIEventBlock != nil
        ]
        
        // Parameters
        var parameters: [[String: Any]] = []
        
        if let parameterTree = audioUnit.parameterTree {
            jsonDict["parameterTree"] = self.extractParameterTree(parameterTree)
        }
        
        // If no parameter tree, try to get standard parameters
        if jsonDict["parameterTree"] == nil {
            parameters.append([
                "name": "Note: No parameter tree available",
                "type": "info",
                "value": "This plugin may not expose parameters via the standard AU parameter tree"
            ])
            jsonDict["parameters"] = parameters
        }
        
        // Format as pretty JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys]) {
            exportedParameterJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
        } else {
            exportedParameterJSON = "{\n  \"error\": \"Failed to serialize parameters\"\n}"
        }
        
        isShowingParameterExport = true
    }
    
    private func extractParameterTree(_ tree: AUParameterTree) -> [String: Any] {
        var result: [String: Any] = [:]
        
        result["name"] = tree.value(forKey: "name") as? String ?? "Root"
        result["key"] = tree.identifier
        
        var children: [[String: Any]] = []
        for child in tree.allParameters {
            children.append(extractParameter(child))
        }
        
        if !children.isEmpty {
            result["children"] = children
        }
        
        return result
    }
    
    private func extractParameter(_ param: AUParameter) -> [String: Any] {
        var paramDict: [String: Any] = [:]
        
        paramDict["identifier"] = param.identifier
        paramDict["displayName"] = param.displayName
        paramDict["address"] = param.address
        paramDict["currentValue"] = param.value
        paramDict["minimumValue"] = param.minValue
        paramDict["maximumValue"] = param.maxValue
        paramDict["defaultValue"] = param.value  // Note: AUParameter doesn't expose default directly, using current as fallback
        paramDict["unit"] = paramUnitToString(param.unit)
        paramDict["unitName"] = paramUnitNameToString(param.unit)
        
        // Note: AUParameter doesn't support KVC for arbitrary keys like "label" or "keyPath"
        // These are not standard AUParameter properties
        
        return paramDict
    }
    
    private func paramUnitToString(_ unit: AudioUnitParameterUnit) -> String {
        switch unit {
        case .generic: return "generic"
        case .indexed: return "indexed"
        case .boolean: return "boolean"
        case .percent: return "percent"
        case .seconds: return "seconds"
        case .sampleFrames: return "sampleFrames"
        case .phase: return "phase"
        case .rate: return "rate"
        case .hertz: return "hertz"
        case .cents: return "cents"
        case .relativeSemiTones: return "relativeSemiTones"
        case .midiNoteNumber: return "midiNoteNumber"
        case .midiController: return "midiController"
        case .midi2Controller: return "midi2Controller"
        case .decibels: return "decibels"
        case .linearGain: return "linearGain"
        case .degrees: return "degrees"
        case .equalPowerCrossfade: return "equalPowerCrossfade"
        case .mixerFaderCurve1: return "mixerFaderCurve1"
        case .pan: return "pan"
        case .meters: return "meters"
        case .absoluteCents: return "absoluteCents"
        case .octaves: return "octaves"
        case .BPM: return "BPM"
        case .beats: return "beats"
        case .milliseconds: return "milliseconds"
        case .ratio: return "ratio"
        case .customUnit: return "customUnit"
        @unknown default: return "unknown(\(unit.rawValue))"
        }
    }
    
    private func paramUnitNameToString(_ unit: AudioUnitParameterUnit) -> String {
        switch unit {
        case .generic: return "Generic"
        case .indexed: return "Indexed"
        case .boolean: return "Boolean"
        case .percent: return "Percent"
        case .seconds: return "Seconds"
        case .sampleFrames: return "Sample Frames"
        case .phase: return "Phase"
        case .rate: return "Rate"
        case .hertz: return "Hz"
        case .cents: return "Cents"
        case .relativeSemiTones: return "Semi-tones"
        case .midiNoteNumber: return "MIDI Note"
        case .midiController: return "MIDI CC"
        case .midi2Controller: return "MIDI 2 CC"
        case .decibels: return "dB"
        case .linearGain: return "Linear Gain"
        case .degrees: return "Degrees"
        case .equalPowerCrossfade: return "Crossfade"
        case .mixerFaderCurve1: return "Fader Curve"
        case .pan: return "Pan"
        case .meters: return "Meters"
        case .absoluteCents: return "Absolute Cents"
        case .octaves: return "Octaves"
        case .BPM: return "BPM"
        case .beats: return "Beats"
        case .milliseconds: return "ms"
        case .ratio: return "Ratio"
        case .customUnit: return "Custom"
        @unknown default: return "Unknown"
        }
    }
    
    private func loadPluginViewController(from audioUnit: AUAudioUnit) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioUnit.requestViewController { viewController in
                Task { @MainActor in
                    if let viewController {
                        self.pluginViewController = viewController
                        continuation.resume(returning: ())
                    } else {
                        // Some plugins don't have UI - this is not always an error
                        // Continue without UI rather than failing completely
                        self.pluginViewController = nil
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }
    
    // MARK: - MCP Methods
    
    func getCurrentParameters() -> [AUParameter]? {
        guard let audioUnit = engineManager.auAudioUnit,
              let parameterTree = audioUnit.parameterTree else {
            return nil
        }
        return Array(parameterTree.allParameters)
    }
    
    func getOscillatorParameters(oscNumber: Int = 1) -> [AUParameter]? {
        guard let params = getCurrentParameters() else { return nil }
        let oscPrefix = "osc\(oscNumber)_"
        return params.filter { param in
            param.identifier.lowercased().hasPrefix(oscPrefix) ||
            param.displayName.lowercased().contains("oscillator \(oscNumber)")
        }
    }
    
    func getParametersByCategory() -> [String: [AUParameter]] {
        guard let params = getCurrentParameters() else { return [:] }
        
        var categorized: [String: [AUParameter]] = [:]
        
        for param in params {
            let id = param.identifier.lowercased()
            let name = param.displayName.lowercased()
            var category = "Other"
            
            if id.contains("osc") || name.contains("oscillator") {
                category = "Oscillators"
            } else if id.contains("filter") || name.contains("filter") {
                category = "Filters"
            } else if id.contains("env") || name.contains("envelope") {
                category = "Envelopes"
            } else if id.contains("lfo") || name.contains("lfo") {
                category = "LFOs"
            } else if id.contains("effects") || name.contains("effect") || name.contains("reverb") || name.contains("delay") || name.contains("chorus") {
                category = "Effects"
            } else if id.contains("amp") || name.contains("amplitude") || name.contains("volume") || name.contains("gain") {
                category = "Amplitude"
            } else if name.contains("modulation") || name.contains("mod") {
                category = "Modulation"
            }
            
            if categorized[category] == nil {
                categorized[category] = []
            }
            categorized[category]?.append(param)
        }
        
        return categorized
    }
    
    func findParameter(identifier: String? = nil, displayName: String? = nil) -> AUParameter? {
        guard let params = getCurrentParameters() else { return nil }
        
        for param in params {
            if let id = identifier {
                if param.identifier.lowercased() == id.lowercased() ||
                   param.identifier.lowercased().contains(id.lowercased()) {
                    return param
                }
            }
            if let name = displayName {
                if param.displayName.lowercased() == name.lowercased() ||
                   param.displayName.lowercased().contains(name.lowercased()) {
                    return param
                }
            }
        }
        return nil
    }
    
    func setParameterValue(identifier: String? = nil, displayName: String? = nil, value: Double) -> Bool {
        guard let param = findParameter(identifier: identifier, displayName: displayName) else {
            print("❌ Parameter not found: identifier=\(identifier ?? "nil"), displayName=\(displayName ?? "nil")")
            return false
        }
        
        let clampedValue = max(param.minValue, min(param.maxValue, AUValue(value)))
        let oldValue = param.value
        
        // Mark that we're setting programmatically (not user interaction)
        isSettingParameterProgrammatically = true
        defer { isSettingParameterProgrammatically = false }
        
        param.setValue(clampedValue, originator: nil)
        
        print("🎛️ Set \(param.displayName): \(oldValue) -> \(clampedValue)")
        
        // Track parameter interaction for learn mode (only if from user interaction, not programmatic)
        // User interactions will trigger through parameter change monitoring
        
        // Force UI update on main thread
        DispatchQueue.main.async {
            if let viewController = self.pluginViewController {
                viewController.view.setNeedsDisplay(viewController.view.bounds)
            }
        }
        
        return true
    }
    
    func getFilterCutoff() -> AUParameter? {
        return findParameter(displayName: "cutoff") ?? findParameter(identifier: "filter_cutoff")
    }
    
    func randomizeParameters(intensity: Double = 0.4, preserveCategories: [String] = [], excludeIds: [String] = []) async throws -> (randomizedCount: Int, intensity: Double) {
        guard let audioUnit = engineManager.auAudioUnit,
              let parameterTree = audioUnit.parameterTree else {
            throw NSError(domain: "PluginHostSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "No plugin loaded or no parameters available"])
        }
        
        let clampedIntensity = max(0.0, min(1.0, intensity))
        var randomizedCount = 0
        var changes: [(AUParameter, AUValue)] = []
        
        // Collect all parameter changes first
        for param in parameterTree.allParameters {
            // Skip if excluded
            if excludeIds.contains(param.identifier) {
                continue
            }
            
            // Skip if category should be preserved
            var shouldPreserve = false
            for category in preserveCategories {
                if param.displayName.contains(category) || param.identifier.contains(category.lowercased()) {
                    shouldPreserve = true
                    break
                }
            }
            if shouldPreserve {
                continue
            }
            
            // Intelligent randomization
            let range = Double(param.maxValue - param.minValue)
            let currentValue = Double(param.value)
            
            // Calculate variation amount
            let variationAmount: Double
            if clampedIntensity < 0.5 {
                variationAmount = range * (0.1 + clampedIntensity * 0.4)
            } else {
                variationAmount = range * (0.3 + (clampedIntensity - 0.5) * 1.4)
            }
            
            // Special handling for different parameter types
            let newValue: Double
            
            if param.unit == .hertz && param.displayName.lowercased().contains("cutoff") {
                // Filter cutoff: logarithmic variation
                let logMin = log10(max(Double(param.minValue), 1.0))
                let logMax = log10(Double(param.maxValue))
                let logCurrent = log10(max(Double(param.minValue), min(Double(param.maxValue), currentValue)))
                let logVariation = (logMax - logMin) * variationAmount / range
                let logNew = logCurrent + (Double.random(in: -1...1) * logVariation)
                newValue = pow(10, max(logMin, min(logMax, logNew)))
            } else if param.displayName.lowercased().contains("wave") || param.identifier.lowercased().contains("wave") {
                // Waveform: discrete selection
                let maxWave = min(Int(param.maxValue), 10)
                newValue = Double(Int.random(in: 0...maxWave))
            } else if param.displayName.lowercased().contains("voices") || param.identifier.lowercased().contains("voices") {
                // Voices: discrete integer
                let minVoices = max(1, Int(param.minValue))
                let maxVoices = Int(param.maxValue)
                newValue = Double(Int.random(in: minVoices...maxVoices))
            } else if param.displayName.lowercased().contains("envelope") || param.displayName.lowercased().contains("env") {
                // Envelope times: exponential variation
                let logMin = log10(max(0.001, Double(param.minValue)))
                let logMax = log10(Double(param.maxValue))
                let logCurrent = log10(max(0.001, currentValue))
                let logVariation = (logMax - logMin) * variationAmount / range
                let logNew = logCurrent + (Double.random(in: -1...1) * logVariation)
                newValue = pow(10, max(logMin, min(logMax, logNew)))
            } else {
                // Default: vary around current value
                let offset = Double.random(in: -1...1) * variationAmount
                newValue = currentValue + offset
            }
            
            // Clamp and store
            let clampedValue = max(param.minValue, min(param.maxValue, AUValue(newValue)))
            changes.append((param, clampedValue))
        }
        
        // Apply all changes - batch update for better performance
        // Use a small delay between changes to allow UI to update
        isSettingParameterProgrammatically = true
        defer { isSettingParameterProgrammatically = false }
        
        for (index, (param, clampedValue)) in changes.enumerated() {
            let oldValue = param.value
            
            // Set the parameter value - this should trigger the plugin to update
            // Use setValue:originator: to ensure proper notification
            param.setValue(clampedValue, originator: nil)
            
            // Debug: log parameter changes
            print("🎲 Randomized \(param.displayName): \(oldValue) -> \(clampedValue)")
            
            randomizedCount += 1
            
            // Small delay to allow UI to update (only for non-instant parameters)
            if index < changes.count - 1 && param.unit != .boolean && param.unit != .indexed {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
            }
        }
        
        // Force UI refresh if plugin view controller exists
        // Some plugins need explicit view updates to reflect parameter changes
        await MainActor.run {
            if let viewController = pluginViewController {
                // Force the view hierarchy to update
                viewController.view.setNeedsDisplay(viewController.view.bounds)
                viewController.view.needsLayout = true
                
                // Also try updating all subviews - some plugins have nested views
                @MainActor
                func updateSubviews(_ view: NSView) {
                    view.setNeedsDisplay(view.bounds)
                    view.needsLayout = true
                    for subview in view.subviews {
                        updateSubviews(subview)
                    }
                }
                updateSubviews(viewController.view)
            }
        }
        
        // Also ensure parameter tree notifications are sent
        if let audioUnit = engineManager.auAudioUnit,
           let parameterTree = audioUnit.parameterTree {
            // Trigger a refresh by accessing parameter values
            // This can help plugins that listen to parameter tree changes
            for param in parameterTree.allParameters {
                _ = param.value // Accessing value can trigger observers
            }
        }
        
        return (randomizedCount, clampedIntensity)
    }
    
    func analyzePatch() async throws -> (summary: String, timbre: (brightness: Double, warmth: Double, roughness: Double, space: Double)) {
        guard let audioUnit = engineManager.auAudioUnit else {
            throw NSError(domain: "PluginHostSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "No plugin loaded"])
        }
        
        // Simple analysis based on parameters
        var filterCutoff: Double = 1000.0
        var attack: Double = 0.05
        var decay: Double = 0.2
        var sustain: Double = 0.7
        
        if let parameterTree = audioUnit.parameterTree {
            for param in parameterTree.allParameters {
                let name = param.displayName.lowercased()
                if name.contains("cutoff") {
                    filterCutoff = Double(param.value)
                } else if name.contains("attack") {
                    attack = Double(param.value)
                } else if name.contains("decay") {
                    decay = Double(param.value)
                } else if name.contains("sustain") {
                    sustain = Double(param.value)
                }
            }
        }
        
        let brightness = min(1.0, filterCutoff / 10000.0)
        let warmth = 0.5 // Could be calculated from resonance
        let roughness = 0.2 // Could be calculated from detune/unison
        let space = 0.3 // Could be calculated from stereo width
        
        var summary = "Short, snappy bass pluck with a bright transient and controlled low-end."
        if attack > 0.1 {
            summary = "Warm pad with gentle attack and smooth decay."
        } else if filterCutoff < 500 {
            summary = "Dark, sub-heavy bass with powerful low-end presence."
        } else if decay > 0.5 && sustain > 0.8 {
            summary = "Long-sustaining pad with slow decay and high sustain."
        }
        
        return (summary, (brightness, warmth, roughness, space))
    }
    
    func sendChatMessage(_ message: String) async throws -> String {
        guard let url = URL(string: "http://localhost:5555/api/chat") else {
            throw NSError(domain: "PluginHostSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["message": message]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            throw NSError(domain: "PluginHostSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return response
    }
    
    func analyzeParameters() async {
        guard let params = getCurrentParameters(), !params.isEmpty else {
            print("⚠️ No parameters to analyze")
            return
        }
        
        let pluginName = currentComponent?.name ?? "Unknown"
        var pluginType = "Unknown"
        
        // Detect plugin type
        if pluginName.lowercased().contains("vital") {
            pluginType = "Vital"
        } else if pluginName.lowercased().contains("serum") {
            pluginType = "Serum"
        }
        
        var analysis = ParameterAnalysis(pluginName: pluginName, pluginType: pluginType)
        
        // Find oscillator level parameters
        for param in params {
            let name = param.displayName.lowercased()
            let id = param.identifier.lowercased()
            
            // Oscillator levels
            if (name.contains("oscillator") || name.contains("osc")) && 
               (name.contains("level") || name.contains("volume") || name.contains("amp")) {
                analysis.oscillatorLevelIds.append(param.identifier)
                print("📊 Found oscillator level: \(param.displayName) (id: \(param.identifier))")
            }
            
            // Filter cutoff
            if name.contains("filter") && name.contains("cutoff") {
                analysis.filterCutoffIds.append(param.identifier)
                print("📊 Found filter cutoff: \(param.displayName) (id: \(param.identifier))")
            }
            
            // Modulation matrix (try various patterns)
            if name.contains("mod") && (name.contains("matrix") || name.contains("modulation")) {
                if name.contains("source") {
                    // Try to find corresponding dest and amount
                    let slotNum = extractSlotNumber(from: name)
                    let destParam = params.first { p in
                        let pName = p.displayName.lowercased()
                        return pName.contains("mod") && (pName.contains("matrix") || pName.contains("modulation")) &&
                               pName.contains("destination") && extractSlotNumber(from: pName) == slotNum
                    }
                    let amountParam = params.first { p in
                        let pName = p.displayName.lowercased()
                        return pName.contains("mod") && (pName.contains("matrix") || pName.contains("modulation")) &&
                               (pName.contains("amount") || pName.contains("depth")) && extractSlotNumber(from: pName) == slotNum
                    }
                    
                    // Ensure array is large enough
                    while analysis.modulationMatrixSlots.count < slotNum {
                        analysis.modulationMatrixSlots.append((nil, nil, nil))
                    }
                    analysis.modulationMatrixSlots[slotNum - 1] = (param, destParam, amountParam)
                    print("📊 Found mod matrix slot \(slotNum): source=\(param.displayName)")
                }
            }
        }
        
        // Also try Serum-specific patterns
        if pluginType == "Serum" {
            // Serum uses different parameter naming
            for param in params {
                let name = param.displayName.lowercased()
                // Serum mod matrix might be named differently
                if name.contains("matrix") && name.contains("source") {
                    let slotNum = extractSlotNumber(from: name)
                    let destParam = params.first { p in
                        let pName = p.displayName.lowercased()
                        return pName.contains("matrix") && pName.contains("destination") && extractSlotNumber(from: pName) == slotNum
                    }
                    let amountParam = params.first { p in
                        let pName = p.displayName.lowercased()
                        return pName.contains("matrix") && (pName.contains("amount") || pName.contains("depth")) && extractSlotNumber(from: pName) == slotNum
                    }
                    
                    if analysis.modulationMatrixSlots.count < slotNum {
                        analysis.modulationMatrixSlots.append((param, destParam, amountParam))
                    }
                }
            }
        }
        
        await MainActor.run {
            self.analyzedParameters = analysis
            print("✅ Parameter analysis complete: \(analysis.oscillatorLevelIds.count) osc levels, \(analysis.filterCutoffIds.count) filters, \(analysis.modulationMatrixSlots.count) mod slots")
        }
    }
    
    private func extractSlotNumber(from text: String) -> Int {
        // Try to extract slot number from parameter name
        let regex = try? NSRegularExpression(pattern: "(\\d+)", options: [])
        let nsString = text as NSString
        if let match = regex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
            return Int(nsString.substring(with: match.range)) ?? 1
        }
        return 1
    }
    
    func startParameterChangeMonitoring() {
        guard !isMonitoringParameterChanges else { return }
        isMonitoringParameterChanges = true
        
        // Initialize parameter values
        if let params = getCurrentParameters() {
            lastParameterValues = Dictionary(uniqueKeysWithValues: params.map { ($0.identifier, $0.value) })
        }
        
        parameterChangeMonitor = Task { @MainActor [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms polling
                
                // Only monitor when learn mode is active
                guard self.midiMapManager.isInLearnMode,
                      self.midiMapManager.pendingCCForLearnMode != nil,
                      !self.isSettingParameterProgrammatically, // Don't trigger on programmatic changes
                      let params = self.getCurrentParameters() else {
                    continue
                }
                
                // Check for parameter value changes (indicating user interaction)
                for param in params {
                    if let oldValue = self.lastParameterValues[param.identifier],
                       abs(param.value - oldValue) > 0.001 { // Significant change
                        // Parameter was changed by user interaction!
                        print("🎯 Learn Mode: Detected parameter change: \(param.displayName)")
                        self.midiMapManager.handleParameterInteraction(
                            parameterId: param.identifier,
                            parameterDisplayName: param.displayName,
                            minValue: param.minValue,
                            maxValue: param.maxValue
                        )
                        // Update stored value
                        self.lastParameterValues[param.identifier] = param.value
                        break // Only handle one parameter change at a time
                    }
                }
                
                // Update stored values
                self.lastParameterValues = Dictionary(uniqueKeysWithValues: params.map { ($0.identifier, $0.value) })
            }
        }
    }
}
