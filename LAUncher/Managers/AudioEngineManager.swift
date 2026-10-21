@preconcurrency import AVFoundation
import AudioToolbox
import Combine
import CoreAudio

@MainActor
final class AudioEngineManager: ObservableObject {
    private let engine = AVAudioEngine()
    private(set) var instrumentNode: AVAudioUnit?
    private(set) var midiInstrument: AVAudioUnitMIDIInstrument?
    private var toneGenerator: AVAudioSourceNode?
    private var toneGeneratorPhase: UnsafeMutablePointer<Double>?
    private var inputNode: AVAudioInputNode?
    private var outputNode1: AVAudioOutputNode?
    private var currentPluginType: OSType = 0

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: Error?
    @Published private(set) var masterGain: Float = 0.8
    @Published private(set) var tempoBPM: Double = 120
    @Published private(set) var isTransportPlaying: Bool = true
    private var transportStartHostTime: UInt64 = AudioGetCurrentHostTime()
    private var transportBeatOffset: Double = 0

    init() {
        configureMainMixerConnection()
        engine.prepare()
        engine.mainMixerNode.outputVolume = masterGain
    }

    var auAudioUnit: AUAudioUnit? {
        instrumentNode?.auAudioUnit
    }

    var sampleRate: Double {
        engine.outputNode.outputFormat(forBus: 0).sampleRate
    }

    var bufferDuration: TimeInterval {
        engine.outputNode.outputPresentationLatency
    }

    func startEngine() throws {
        guard !engine.isRunning else {
            isRunning = true
            return
        }

        do {
            try engine.start()
            isRunning = true
            lastError = nil
        } catch {
            lastError = Self.friendlyError(from: error)
            isRunning = false
            throw lastError ?? error
        }
    }

    func stopEngine() {
        guard engine.isRunning else {
            isRunning = false
            return
        }

        engine.stop()
        isRunning = false
    }

    func setMasterGain(_ value: Float) {
        let clamped = max(0.0, min(1.0, value))
        masterGain = clamped
        engine.mainMixerNode.outputVolume = clamped
    }

    func setTempo(_ bpm: Double) {
        let clamped = max(10.0, min(400.0, bpm))
        tempoBPM = clamped
        // When tempo changes, reset transport timing to avoid beat position jumps
        if isTransportPlaying {
            transportStartHostTime = AudioGetCurrentHostTime()
            transportBeatOffset = 0
        }
    }

    func unloadPlugin() {
        if engine.isRunning {
            stopEngine()
        }
        if let node = instrumentNode {
            engine.disconnectNodeInput(node)
            engine.detach(node)
        }
        clearToneGenerator()
        instrumentNode = nil
        midiInstrument = nil
        currentPluginType = 0
    }

    func loadPlugin(componentDescription: AudioComponentDescription, component: AVAudioUnitComponent? = nil) async throws -> AVAudioUnit {
        let pluginType = componentDescription.componentType
        let wasRunning = engine.isRunning
        if wasRunning {
            stopEngine()
        }

        let newNode = try await instantiatePlugin(with: componentDescription, component: component)

        // Unload existing plugin / tone gen
        if let existing = instrumentNode {
            engine.disconnectNodeInput(existing)
            engine.detach(existing)
        }
        clearToneGenerator()

        engine.attach(newNode)
        currentPluginType = pluginType
        midiInstrument = newNode as? AVAudioUnitMIDIInstrument
        instrumentNode = newNode

        installHostSync(on: newNode.auAudioUnit)

        let needsAudioInput = pluginType == kAudioUnitType_Effect || pluginType == kAudioUnitType_MusicEffect
        if needsAudioInput {
            try startEffectGraphTryingFormats(plugin: newNode)
        } else {
            do {
                try wirePluginGraph(plugin: newNode, pluginType: pluginType, preferredFormat: nil)
                configureMainMixerConnection()
                try startEngine()
            } catch {
                disconnectInputFromGraph()
                configureMainMixerConnection()
                try startEngine()
            }
        }

        return newNode
    }

    /// Try several bus formats so picky Music FX (Ohmicide, etc.) can load.
    private func startEffectGraphTryingFormats(plugin: AVAudioUnit) throws {
        let candidates = effectFormatCandidates(for: plugin)
        var lastError: Error?

        for (index, format) in candidates.enumerated() {
            do {
                resetEffectConnections(plugin: plugin)
                // Later candidates force test-tone only (avoids aggregate input channel fights).
                forceToneOnlyForEffect = index >= 3
                if forceToneOnlyForEffect {
                    inputNode = nil
                }
                try wirePluginGraph(plugin: plugin, pluginType: currentPluginType, preferredFormat: format)
                configureMainMixerConnection()
                try startEngine()
                forceToneOnlyForEffect = false
                print("✅ FX graph started with format candidate #\(index): \(describeFormat(format))")
                return
            } catch {
                lastError = error
                forceToneOnlyForEffect = false
                print("⚠️ FX format candidate #\(index) failed (\(describeFormat(format))): \(error.localizedDescription)")
                stopEngine()
            }
        }

        throw lastError ?? Self.friendlyNSError(
            status: kAudioUnitErr_FormatNotSupported,
            fallback: "This effect rejected the current device format — open Settings and try 48 kHz or a different output."
        )
    }

    private func resetEffectConnections(plugin: AVAudioUnit) {
        clearToneGenerator()
        engine.disconnectNodeInput(plugin)
        let outs = engine.outputConnectionPoints(for: plugin, outputBus: 0)
        for connection in outs {
            if let target = connection.node {
                engine.disconnectNodeInput(target, bus: connection.bus)
            }
        }
        disconnectInputFromGraph()
    }

    private func effectFormatCandidates(for plugin: AVAudioUnit) -> [AVAudioFormat?] {
        var list: [AVAudioFormat?] = [nil] // let AVAudioEngine negotiate first

        let outHW = engine.outputNode.outputFormat(forBus: 0)
        if outHW.channelCount > 0 { list.append(outHW) }

        let pluginOut = plugin.outputFormat(forBus: 0)
        if pluginOut.channelCount > 0 { list.append(pluginOut) }

        let sr = outHW.sampleRate > 0 ? outHW.sampleRate : 48_000
        if let stereo = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) {
            list.append(stereo)
        }
        if let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) {
            list.append(mono)
        }
        // Explicit non-interleaved float stereo (common AU bus layout)
        if let floatStereo = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sr,
            channels: 2,
            interleaved: false
        ) {
            list.append(floatStereo)
        }

        return list
    }

    private func describeFormat(_ format: AVAudioFormat?) -> String {
        guard let format else { return "nil (negotiate)" }
        return "\(format.sampleRate) Hz · \(format.channelCount) ch"
    }

    private func clearToneGenerator() {
        if let existingGenerator = toneGenerator {
            engine.disconnectNodeInput(existingGenerator)
            engine.detach(existingGenerator)
        }
        if let phase = toneGeneratorPhase {
            phase.deallocate()
            toneGeneratorPhase = nil
        }
        toneGenerator = nil
    }

    private var pluginNeedsAudioInput: Bool {
        currentPluginType == kAudioUnitType_Effect || currentPluginType == kAudioUnitType_MusicEffect
    }

    /// Build plugin → mixer (and input/tone → plugin for FX only). Never route mic into instrument graphs.
    private func wirePluginGraph(plugin: AVAudioUnit, pluginType: OSType, preferredFormat: AVAudioFormat?) throws {
        let mixer = engine.mainMixerNode
        let needsAudioInput = pluginType == kAudioUnitType_Effect || pluginType == kAudioUnitType_MusicEffect

        if needsAudioInput {
            if !forceToneOnlyForEffect, inputNode == nil, preferredInputDeviceID != nil {
                inputNode = engine.inputNode
                if let id = preferredInputDeviceID {
                    try? setCurrentDevice(id, on: engine.inputNode)
                }
            }

            // Prefer an explicit format; otherwise nil lets the engine negotiate.
            let linkFormat: AVAudioFormat? = preferredFormat

            if let input = inputNode, !forceToneOnlyForEffect {
                let inFormat = input.outputFormat(forBus: 0)
                let srcFormat = linkFormat ?? (inFormat.channelCount > 0 ? inFormat : nil)
                engine.connect(input, to: plugin, format: srcFormat)
            } else {
                let (generator, phase) = createToneGenerator()
                engine.attach(generator)
                engine.connect(generator, to: plugin, format: linkFormat)
                toneGenerator = generator
                toneGeneratorPhase = phase
            }
            engine.connect(plugin, to: mixer, format: linkFormat)
        } else {
            disconnectInputFromGraph()
            let mixerFormat = mixer.inputFormat(forBus: 0)
            let format = preferredFormat ?? (mixerFormat.channelCount > 0 ? mixerFormat : nil)
            engine.connect(plugin, to: mixer, format: format)
        }
    }

    private func disconnectInputFromGraph() {
        guard let input = inputNode else { return }
        let connections = engine.outputConnectionPoints(for: input, outputBus: 0)
        for connection in connections {
            if let target = connection.node {
                engine.disconnectNodeInput(target, bus: connection.bus)
            }
        }
    }

    func loadInstrument(componentDescription: AudioComponentDescription) async throws -> AVAudioUnit {
        return try await loadPlugin(componentDescription: componentDescription)
    }

    func unloadInstrument() {
        unloadPlugin()
    }

    func send(midiEvent: MidiEvent) {
        guard let node = instrumentNode else { return }

        let status = midiEvent.statusByte
        let data1 = midiEvent.data1
        let data2 = midiEvent.data2

        if let midiInstrument {
            midiInstrument.sendMIDIEvent(status, data1: data1, data2: data2)
            return
        }

        guard let scheduleBlock = node.auAudioUnit.scheduleMIDIEventBlock else { return }

        let payload: [UInt8] = [status, data1, data2]
        payload.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            scheduleBlock(AUEventSampleTimeImmediate, 0, buffer.count, baseAddress)
        }
    }

    func loadPlugin(componentDescription: AudioComponentDescription) async throws -> AVAudioUnit {
        return try await loadPlugin(componentDescription: componentDescription, component: nil)
    }

    private func instantiatePlugin(with description: AudioComponentDescription, component: AVAudioUnitComponent? = nil) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            // Debug: Log the description we're trying to instantiate
            print("   📦 Instantiating with description:")
            print("      Type: \(description.componentType) (\(fourCCToString(description.componentType)))")
            print("      SubType: \(description.componentSubType) (\(fourCCToString(description.componentSubType)))")
            print("      Manufacturer: \(description.componentManufacturer) (\(fourCCToString(description.componentManufacturer)))")
            print("      Flags: \(description.componentFlags)")
            print("      FlagsMask: \(description.componentFlagsMask)")
            
            // Determine if this is likely an AU 2 or AUv3 plugin
            // Check via typeName - AUv3 plugins typically have "Music Device" or similar, but we can't reliably detect
            // Just log what we can
            if let component = component {
                print("   Component name: \(component.name)")
                print("   Component type name: \(component.typeName)")
                // componentURL is deprecated, but we can still try to access it for debugging
                #if swift(>=5.0)
                if #available(macOS 10.11, *) {
                    // Fallback: just note we can't determine type from URL
                    print("   Note: Using component description for loading")
                }
                #endif
            }
            
            // Prefer out-of-process for third-party AUs (FabFilter Music FX, etc.) — more stable in hosts.
            let primary: AudioComponentInstantiationOptions = .loadOutOfProcess
            AVAudioUnit.instantiate(with: description, options: primary) { auAudioUnit, error in
                if let auAudioUnit {
                    print("   ✅ Instantiation successful (out-of-process)")
                    continuation.resume(returning: auAudioUnit)
                    return
                }

                // Retry in-process for older AU2 components that reject out-of-process.
                AVAudioUnit.instantiate(with: description, options: []) { retryUnit, retryError in
                    if let retryUnit {
                        print("   ✅ Instantiation successful (in-process fallback)")
                        continuation.resume(returning: retryUnit)
                        return
                    }
                    let capturedError = retryError ?? error ?? NSError(
                        domain: "AudioEngineManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown error instantiating plugin"]
                    )
                    let capturedDescription = description
                    let capturedComponent = component
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.handleInstantiationError(
                            error: capturedError,
                            description: capturedDescription,
                            component: capturedComponent,
                            continuation: continuation
                        )
                    }
                }
            }
        }
    }
    
    private func handleInstantiationError(error: Error, description: AudioComponentDescription, component: AVAudioUnitComponent?, continuation: CheckedContinuation<AVAudioUnit, Error>) {
        let nsError = error as NSError
        let errorCode = nsError.code
        
        // If we get -3000 and this might be an AUv3 plugin, log additional info
        if errorCode == -3000 {
            print("   ⚠️ Error -3000 detected. This might be an AUv3 app extension issue.")
            if let component = component {
                print("   Component name: \(component.name)")
                print("   Component type name: \(component.typeName)")
                // componentURL is deprecated, skip it
            }
            print("   Note: AUv3 plugins require proper entitlements in the host app.")
            print("   The app may need 'com.apple.security.cs.disable-library-validation' entitlement.")
        }
        
        let errorDescription: String
        
        // Provide more helpful error messages based on error codes
        switch errorCode {
        case -3000:
            errorDescription = "Cannot instantiate plugin (error -3000). Often missing entitlements (Disable Library Validation) or an AUv3 install issue. Try `auval -a`."
        case -1:
            errorDescription = "Plugin failed to open (OSStatus -1). Common with Music Effects if the component is busy, blocked by Gatekeeper, or needs a rescan. Try Rescan, then quit/reopen the plugin’s vendor app once."
        case -10879:
            errorDescription = "Audio graph error (Invalid Property / -10879). Usually a bad input/output format when loading an effect. Pick an output device in the Inspector and try again."
        case -10814:
            errorDescription = "Plugin not found or not properly installed. Check /Library/Audio/Plug-Ins/Components/ or ~/Library/Audio/Plug-Ins/Components/"
        case -50:
            errorDescription = "Invalid plugin parameter. The plugin may be corrupted or incompatible."
        case -10810:
            errorDescription = "Plugin validation failed. The plugin may be corrupted or incompatible with this macOS version."
        default:
            errorDescription = nsError.localizedDescription.isEmpty
                ? "Unknown error (code: \(errorCode)). Domain: \(nsError.domain)"
                : nsError.localizedDescription
        }
        
        print("   ❌ Instantiation failed with error code \(errorCode)")
        print("   Error details: \(nsError.localizedDescription)")
        if let underlyingDesc = nsError.userInfo[NSLocalizedFailureReasonErrorKey] {
            print("   Failure reason: \(underlyingDesc)")
        }
        
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: errorDescription
        ]
        let underlyingError = error as NSError
        userInfo[NSUnderlyingErrorKey] = underlyingError
        
        continuation.resume(throwing: NSError(
            domain: "AudioEngineManager",
            code: Int(errorCode),
            userInfo: userInfo
        ))
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
    
    private func createToneGenerator() -> (AVAudioSourceNode, UnsafeMutablePointer<Double>) {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let phaseRef = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        phaseRef.initialize(to: 0)
        let frequency: Double = 440.0 // A4 note
        let phaseIncrement = frequency / sampleRate
        
        let generator = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let audioBufferListPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            for frame in 0..<Int(frameCount) {
                let sample = sin(2.0 * Double.pi * phaseRef.pointee)
                let value = Float(sample * 0.3) // Low volume to avoid clipping
                
                for buffer in audioBufferListPointer {
                    if let channelData = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        channelData[frame] = value
                    }
                }
                
                phaseRef.pointee += phaseIncrement
                if phaseRef.pointee >= 1.0 {
                    phaseRef.pointee -= 1.0
                }
            }
            
            return noErr
        }
        
        return (generator, phaseRef)
    }

    func setInputDevice(_ device: AudioDevice?) throws {
        let wasRunning = engine.isRunning
        if wasRunning { stopEngine() }

        if let device {
            // Touching inputNode enables the input side of AVAudioEngine — only keep it
            // when an effect needs audio in. Still record the preferred device for FX loads.
            _ = engine.inputNode // ensure node exists
            try setCurrentDevice(device.id, on: engine.inputNode)
            inputNode = pluginNeedsAudioInput ? engine.inputNode : nil
            preferredInputDeviceID = device.id
        } else {
            preferredInputDeviceID = nil
            inputNode = nil
        }

        try rebuildGraphKeepingPlugin()
        if wasRunning {
            try startEngine()
        }
    }

    func setOutputDevice(_ device: AudioDevice?) throws {
        let wasRunning = engine.isRunning
        if wasRunning { stopEngine() }

        if let device {
            try setCurrentDevice(device.id, on: engine.outputNode)
            outputNode1 = engine.outputNode
            configureMainMixerConnection()
            engine.mainMixerNode.outputVolume = masterGain
        } else {
            let mainMixer = engine.mainMixerNode
            let output = engine.outputNode
            if engine.outputConnectionPoints(for: mainMixer, outputBus: 0).contains(where: { $0.node == output }) {
                engine.disconnectNodeInput(output)
            }
            outputNode1 = nil
            engine.mainMixerNode.outputVolume = 0
        }

        if wasRunning {
            try startEngine()
        }
    }

    private var preferredInputDeviceID: AudioDeviceID?
    /// When true, FX graphs skip hardware input and use the test tone (format fallbacks).
    private var forceToneOnlyForEffect = false

    /// Set HAL CurrentDevice on this engine node only — do not change macOS system defaults.
    private func setCurrentDevice(_ deviceID: AudioDeviceID, on node: AVAudioNode) throws {
        let unit: AudioUnit?
        if let output = node as? AVAudioOutputNode {
            unit = output.audioUnit
        } else if let input = node as? AVAudioInputNode {
            unit = input.audioUnit
        } else {
            unit = nil
        }
        guard let audioUnit = unit else {
            throw Self.friendlyNSError(
                status: kAudioUnitErr_InvalidProperty,
                fallback: "Could not access audio unit for device selection."
            )
        }
        var id = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            size
        )
        if status != noErr {
            throw Self.friendlyNSError(status: status, fallback: "Failed to set audio device.")
        }
    }

    private static func friendlyError(from error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == NSOSStatusErrorDomain || ns.domain == "com.apple.coreaudio.avfaudio" {
            return friendlyNSError(status: OSStatus(ns.code), fallback: ns.localizedDescription)
        }
        if ns.code == -10879 || ns.code == -1 {
            return friendlyNSError(status: OSStatus(ns.code), fallback: ns.localizedDescription)
        }
        return error
    }

    private static func friendlyNSError(status: OSStatus, fallback: String) -> NSError {
        let message: String
        switch status {
        case -10879:
            message = "Audio graph error (−10879 Invalid Property). Check input/output devices, then reload the plugin."
        case -1:
            message = "Audio operation failed (OSStatus −1). For Music Effects like Pro-Q, try Rescan, then load again."
        case kAudioUnitErr_FormatNotSupported:
            message = "This effect rejected the current device format — open Settings and try 48 kHz or a different output."
        case kAudioUnitErr_FailedInitialization:
            message = "Plugin failed to initialize. Quit other hosts using it and try again."
        default:
            message = fallback.isEmpty ? "Audio error (OSStatus \(status))." : fallback
        }
        return NSError(
            domain: "AudioEngineManager",
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func rebuildGraphKeepingPlugin() throws {
        clearToneGenerator()
        if let plugin = instrumentNode {
            // Disconnect plugin outputs then rewire
            let outs = engine.outputConnectionPoints(for: plugin, outputBus: 0)
            for connection in outs {
                if let target = connection.node {
                    engine.disconnectNodeInput(target, bus: connection.bus)
                }
            }
            engine.disconnectNodeInput(plugin)
            if pluginNeedsAudioInput {
                try startEffectGraphTryingFormats(plugin: plugin)
            } else {
                try wirePluginGraph(plugin: plugin, pluginType: currentPluginType, preferredFormat: nil)
            }
        } else {
            disconnectInputFromGraph()
        }
        configureMainMixerConnection()
    }

    private func configureMainMixerConnection() {
        let output = engine.outputNode
        let mainMixer = engine.mainMixerNode
        let format = output.inputFormat(forBus: 0)

        if !engine.outputConnectionPoints(for: mainMixer, outputBus: 0).contains(where: { $0.node == output }) {
            engine.connect(mainMixer, to: output, format: format.channelCount > 0 ? format : nil)
        }
    }

    // MARK: - Host Sync Helpers
    private func currentElapsedSeconds() -> Double {
        let now = AudioGetCurrentHostTime()
        let delta = now &- transportStartHostTime
        let nanos = AudioConvertHostTimeToNanos(delta)
        return Double(nanos) / 1_000_000_000.0
    }

    private func currentBeatPosition() -> Double {
        guard isTransportPlaying else {
            return transportBeatOffset
        }
        let beatsPerSecond = tempoBPM / 60.0
        return transportBeatOffset + currentElapsedSeconds() * beatsPerSecond
    }

    func setTransportPlaying(_ playing: Bool) {
        if playing == isTransportPlaying { return }
        
        if playing {
            // Resuming: preserve current beat position (from when paused), reset start time
            let preservedBeat = transportBeatOffset
            transportBeatOffset = preservedBeat
            transportStartHostTime = AudioGetCurrentHostTime()
        } else {
            // Pausing: freeze beat at current position
            // Calculate current beat before pausing
            let beatsPerSecond = tempoBPM / 60.0
            let currentBeat = transportBeatOffset + currentElapsedSeconds() * beatsPerSecond
            transportBeatOffset = currentBeat
        }
        
        isTransportPlaying = playing
    }

    private func installHostSync(on au: AUAudioUnit) {
        if #available(macOS 10.13, *) {
            au.musicalContextBlock = { (tempo: UnsafeMutablePointer<Double>?,
                                        timeSignatureNumerator: UnsafeMutablePointer<Double>?,
                                        timeSignatureDenominator: UnsafeMutablePointer<Int>?,
                                        currentBeatPosition: UnsafeMutablePointer<Double>?,
                                        sampleOffsetToNextBeat: UnsafeMutablePointer<Int>?,
                                        currentMeasureDownbeat: UnsafeMutablePointer<Double>?) -> Bool in
                if let tempo { tempo.pointee = self.tempoBPM }
                if let timeSignatureNumerator { timeSignatureNumerator.pointee = 4.0 }
                if let timeSignatureDenominator { timeSignatureDenominator.pointee = 4 }
                if let currentBeatPosition { currentBeatPosition.pointee = self.currentBeatPosition() }
                if let sampleOffsetToNextBeat {
                    let beats = self.currentBeatPosition()
                    let nextBeat = ceil(beats)
                    let beatOffset = nextBeat - beats
                    let samplesPerBeat = (60.0 / self.tempoBPM) * self.sampleRate
                    sampleOffsetToNextBeat.pointee = Int(beatOffset * samplesPerBeat)
                }
                if let currentMeasureDownbeat {
                    let beats = self.currentBeatPosition()
                    currentMeasureDownbeat.pointee = floor(beats / 4.0) * 4.0
                }
                return true
            }

            au.transportStateBlock = { (transportStateFlags: UnsafeMutablePointer<AUHostTransportStateFlags>?,
                                         currentSamplePosition: UnsafeMutablePointer<Double>?,
                                         currentBeatPosition: UnsafeMutablePointer<Double>?,
                                         currentSampleTime: UnsafeMutablePointer<Double>?) -> Bool in
                if let transportStateFlags {
                    var flags = AUHostTransportStateFlags()
                    if self.isTransportPlaying { flags.insert(.moving) }
                    transportStateFlags.pointee = flags
                }
                if let currentSamplePosition {
                    currentSamplePosition.pointee = self.currentElapsedSeconds() * self.sampleRate
                }
                if let currentBeatPosition {
                    currentBeatPosition.pointee = self.currentBeatPosition()
                }
                if let currentSampleTime {
                    currentSampleTime.pointee = self.currentElapsedSeconds()
                }
                return true
            }
        }
    }
}
