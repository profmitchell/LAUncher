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
    private var outputNode2: AVAudioOutputNode?
    private var currentPluginType: OSType = 0

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: Error?

    init() {
        configureMainMixerConnection()
        engine.prepare()
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
            lastError = error
            isRunning = false
            throw error
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

    func unloadPlugin() {
        if let node = instrumentNode {
            engine.disconnectNodeInput(node)
            engine.detach(node)
        }
        
        if let generator = toneGenerator {
            engine.disconnectNodeInput(generator)
            engine.detach(generator)
        }
        
        // Clean up phase memory
        if let phase = toneGeneratorPhase {
            phase.deallocate()
            toneGeneratorPhase = nil
        }

        instrumentNode = nil
        midiInstrument = nil
        toneGenerator = nil
    }

    func loadPlugin(componentDescription: AudioComponentDescription, component: AVAudioUnitComponent? = nil) async throws -> AVAudioUnit {
        let pluginType = componentDescription.componentType
        
        let newNode = try await instantiatePlugin(with: componentDescription, component: component)

        // Unload existing plugin
        if let existing = instrumentNode {
            engine.disconnectNodeInput(existing)
            engine.detach(existing)
        }
        
        if let existingGenerator = toneGenerator {
            engine.disconnectNodeInput(existingGenerator)
            engine.detach(existingGenerator)
        }
        
        // Clean up existing phase memory
        if let phase = toneGeneratorPhase {
            phase.deallocate()
            toneGeneratorPhase = nil
        }

        engine.attach(newNode)
        
        // Store plugin type for routing decisions
        currentPluginType = pluginType
        
        // Route based on plugin type
        if pluginType == kAudioUnitType_Effect {
            // Effects need input signal - check if we have input, otherwise use tone generator
            if let input = inputNode {
                engine.connect(input, to: newNode, format: input.outputFormat(forBus: 0))
            } else {
                // No input device, use tone generator
                let (generator, phase) = createToneGenerator()
                engine.attach(generator)
                engine.connect(generator, to: newNode, format: nil)
                toneGenerator = generator
                toneGeneratorPhase = phase
            }
            engine.connect(newNode, to: engine.mainMixerNode, format: nil)
        } else {
            // Instruments, generators, etc. connect directly to mixer
            engine.connect(newNode, to: engine.mainMixerNode, format: nil)
        }
        
        configureMainMixerConnection()
        midiInstrument = newNode as? AVAudioUnitMIDIInstrument
        instrumentNode = newNode

        if !engine.isRunning {
            try startEngine()
        }

        return newNode
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
            
            // Try instantiation - empty options typically works for both AU 2 and AUv3
            // AU 2 plugins may load in-process by default, AUv3 always out-of-process
            let options: AudioComponentInstantiationOptions = []
            
            AVAudioUnit.instantiate(with: description, options: options) { auAudioUnit, error in
                if let auAudioUnit {
                    print("   ✅ Instantiation successful")
                    continuation.resume(returning: auAudioUnit)
                } else if let error = error {
                    // If initial attempt fails, try logging additional info and report error
                    // Capture values before async call to avoid concurrency warnings
                    let capturedError = error
                    let capturedDescription = description
                    let capturedComponent = component
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.handleInstantiationError(error: capturedError, description: capturedDescription, component: capturedComponent, continuation: continuation)
                    }
                } else {
                    continuation.resume(throwing: NSError(domain: "AudioEngineManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error instantiating plugin"]))
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
            errorDescription = "Cannot instantiate plugin (error -3000). This is often caused by:\n• Missing entitlements: The app may need 'Disable Library Validation'\n• AUv3 app extension not properly installed\n• Plugin needs to be validated first\n• Try: auval -a to validate plugins, or check Xcode project entitlements"
        case -10814:
            errorDescription = "Plugin not found or not properly installed. Make sure the plugin is installed in /Library/Audio/Plug-Ins/Components/ or ~/Library/Audio/Plug-Ins/Components/"
        case -50:
            errorDescription = "Invalid plugin parameter. The plugin may be corrupted or incompatible."
        case -10810:
            errorDescription = "Plugin validation failed. The plugin may be corrupted or incompatible with this version of macOS."
        default:
            errorDescription = nsError.localizedDescription.isEmpty ? "Unknown error (code: \(errorCode)). Domain: \(nsError.domain)" : nsError.localizedDescription
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
        // Stop engine first
        let wasRunning = isRunning
        if isRunning {
            stopEngine()
        }
        
        // Configure input node
        if let device = device {
            // Set the input device using CoreAudio
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var deviceID = device.id
            let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                dataSize,
                &deviceID
            )
            
            if status != noErr {
                throw NSError(domain: "AudioEngineManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set input device"])
            }
            
            // Input node will use the default input device
            inputNode = engine.inputNode
        } else {
            inputNode = nil
        }
        
        // Reconfigure routing
        reconfigureRouting()
        
        // Restart if was running
        if wasRunning {
            try startEngine()
        }
    }
    
    func setOutputDevices(output1: AudioDevice?, output2: AudioDevice?) throws {
        // Stop engine first
        let wasRunning = isRunning
        if isRunning {
            stopEngine()
        }
        
        // Configure output device 1 (primary stereo output)
        // AVAudioEngine only supports one output device
        // We use output1 as primary, output2 is tracked but uses same hardware output
        if let device1 = output1 {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var deviceID = device1.id
            let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                dataSize,
                &deviceID
            )
            
            if status != noErr {
                throw NSError(domain: "AudioEngineManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set output device 1"])
            }
        }
        
        outputNode1 = output1 != nil ? engine.outputNode : nil
        
        // Note: Output 2 would require a separate audio engine or multi-output setup
        // For now, we track it but use the same output node
        // In a future implementation, we could create an aggregate device or second engine
        outputNode2 = output2 != nil ? engine.outputNode : nil
        
        // Don't reconfigure routing - just ensure mixer is connected
        // This prevents breaking existing connections
        configureMainMixerConnection()
        
        // Restart if was running
        if wasRunning {
            try startEngine()
        }
    }
    
    private func reconfigureRouting() {
        // Stop engine before reconfiguring
        let wasRunning = isRunning
        if isRunning {
            stopEngine()
        }
        
        // Disconnect all existing connections properly
        // Disconnect plugin from mixer if it exists
        if let plugin = instrumentNode {
            // Check if plugin is connected to mixer
            let pluginConnections = engine.outputConnectionPoints(for: plugin, outputBus: 0)
            for connection in pluginConnections {
                if connection.node == engine.mainMixerNode {
                    engine.disconnectNodeInput(engine.mainMixerNode, bus: connection.bus)
                }
            }
        }
        
        // Disconnect input node if it exists
        if let input = inputNode {
            // Disconnect any output connections from input
            let inputConnections = engine.outputConnectionPoints(for: input, outputBus: 0)
            for connection in inputConnections {
                if let targetNode = connection.node {
                    if targetNode == instrumentNode {
                        // Disconnect from plugin
                        engine.disconnectNodeInput(targetNode, bus: connection.bus)
                    } else if targetNode == engine.mainMixerNode {
                        // Disconnect from mixer
                        engine.disconnectNodeInput(engine.mainMixerNode, bus: connection.bus)
                    }
                }
            }
        }
        
        // Disconnect tone generator if it exists
        if let generator = toneGenerator {
            let generatorConnections = engine.outputConnectionPoints(for: generator, outputBus: 0)
            for connection in generatorConnections {
                if let targetNode = connection.node {
                    if targetNode == instrumentNode {
                        // Disconnect from plugin
                        engine.disconnectNodeInput(targetNode, bus: connection.bus)
                    } else if targetNode == engine.mainMixerNode {
                        // Disconnect from mixer
                        engine.disconnectNodeInput(engine.mainMixerNode, bus: connection.bus)
                    }
                }
            }
        }
        
        // Rebuild routing
        if let input = inputNode {
            // Connect input to plugin if it's an effect
            if let plugin = instrumentNode,
               currentPluginType == kAudioUnitType_Effect {
                engine.connect(input, to: plugin, format: input.outputFormat(forBus: 0))
                engine.connect(plugin, to: engine.mainMixerNode, format: nil)
            } else {
                // Connect input to mixer
                engine.connect(input, to: engine.mainMixerNode, format: input.outputFormat(forBus: 0))
            }
        }
        
        // Ensure mixer is connected to output
        configureMainMixerConnection()
        
        // Restart if was running
        if wasRunning {
            try? startEngine()
        }
    }

    private func configureMainMixerConnection() {
        let output = engine.outputNode
        let mainMixer = engine.mainMixerNode
        let format = output.inputFormat(forBus: 0)

        if !engine.outputConnectionPoints(for: mainMixer, outputBus: 0).contains(where: { $0.node == output }) {
            engine.connect(mainMixer, to: output, format: format.channelCount > 0 ? format : nil)
        }
    }
}
