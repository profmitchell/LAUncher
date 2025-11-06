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
    @Published private(set) var lastMidiEvent: MidiEvent?

    @Published var isShowingPluginPicker = false
    @Published var isMusicalTypingEnabled = false
    @Published var isShowingParameterExport = false
    @Published var exportedParameterJSON: String = ""
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

    @Published var selectedInputDevice: AudioDevice? {
        didSet {
            if selectedInputDevice != oldValue {
                try? engineManager.setInputDevice(selectedInputDevice)
            }
        }
    }
    
    @Published var selectedOutputLeft: AudioDevice? {
        didSet {
            if selectedOutputLeft != oldValue {
                try? engineManager.setOutputDevices(left: selectedOutputLeft, right: selectedOutputRight)
            }
        }
    }
    
    @Published var selectedOutputRight: AudioDevice? {
        didSet {
            if selectedOutputRight != oldValue {
                try? engineManager.setOutputDevices(left: selectedOutputLeft, right: selectedOutputRight)
            }
        }
    }
    
    var inputDevices: [AudioDevice] {
        audioDeviceManager.inputDevices
    }
    
    var outputDevices: [AudioDevice] {
        audioDeviceManager.outputDevices
    }

    private var cancellables: Set<AnyCancellable> = []

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
        if selectedOutputLeft == nil {
            selectedOutputLeft = audioDeviceManager.outputDevices.first
        }
        if selectedOutputRight == nil {
            selectedOutputRight = audioDeviceManager.outputDevices.first
        }
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
        engineState = .stopped
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
            self?.handleMidi(event: event)
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
}
