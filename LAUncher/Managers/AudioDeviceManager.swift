import Foundation
import CoreAudio
import AVFoundation
import Combine

struct AudioDevice: Identifiable, Equatable, Hashable {
    var id: AudioDeviceID
    let name: String
    let isInput: Bool
    let isOutput: Bool
    let channels: Int
    /// Channels on the input scope (when known).
    let inputChannels: Int

    /// Human-readable label for menus (strips CoreAudio noise, adds channel hint).
    var displayName: String {
        var cleaned = name
        if cleaned.hasPrefix("CADefaultDevice/") {
            cleaned = String(cleaned.dropFirst("CADefaultDevice/".count))
        }
        if cleaned.lowercased().hasPrefix("aggregate") {
            cleaned = "Aggregate Device"
        }
        // Truncate very long UID-looking tails
        if cleaned.count > 40, let dash = cleaned.lastIndex(of: "-") {
            let head = cleaned[..<dash]
            if head.count >= 8 { cleaned = String(head) }
        }

        if isInput && isOutput {
            return "\(cleaned) (\(inputChannels) in / \(channels) out)"
        }
        if isInput {
            return "\(cleaned) (\(max(inputChannels, channels)) ch in)"
        }
        return "\(cleaned) (\(channels) ch)"
    }
    
    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    
    func refreshDevices() {
        refreshInputDevices()
        refreshOutputDevices()
    }
    
    private func refreshInputDevices() {
        var devices: [AudioDevice] = []
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("Failed to get device list size: \(status)")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("Failed to get device list: \(status)")
            return
        }
        
        for deviceID in deviceIDs {
            if let device = getDeviceInfo(deviceID: deviceID) {
                if device.isInput {
                    devices.append(device)
                }
            }
        }
        
        inputDevices = devices.sorted { $0.name < $1.name }
        
        // Add default input option
        if let defaultInput = getDefaultInputDevice() {
            if !inputDevices.contains(where: { $0.id == defaultInput.id }) {
                inputDevices.insert(defaultInput, at: 0)
            }
        }
    }
    
    private func refreshOutputDevices() {
        var devices: [AudioDevice] = []
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("Failed to get device list size: \(status)")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("Failed to get device list: \(status)")
            return
        }
        
        for deviceID in deviceIDs {
            if let device = getDeviceInfo(deviceID: deviceID) {
                if device.isOutput {
                    devices.append(device)
                }
            }
        }
        
        outputDevices = devices.sorted { $0.name < $1.name }
        
        // Add default output option
        if let defaultOutput = getDefaultOutputDevice() {
            if !outputDevices.contains(where: { $0.id == defaultOutput.id }) {
                outputDevices.insert(defaultOutput, at: 0)
            }
        }
    }
    
    private func getDeviceInfo(deviceID: AudioDeviceID) -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var nameRef: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &nameRef
        )
        
        guard status == noErr, let name = nameRef?.takeRetainedValue() as String? else {
            return nil
        }
        
        // Check if device has input
        var hasInput = false
        propertyAddress.mSelector = kAudioDevicePropertyStreams
        propertyAddress.mScope = kAudioDevicePropertyScopeInput
        dataSize = 0
        status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        if status == noErr && dataSize > 0 {
            hasInput = true
        }
        
        // Check if device has output
        var hasOutput = false
        propertyAddress.mScope = kAudioDevicePropertyScopeOutput
        dataSize = 0
        status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        if status == noErr && dataSize > 0 {
            hasOutput = true
        }
        
        let outputChannels = channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput)
        let inputChannels = channelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)

        return AudioDevice(
            id: deviceID,
            name: name,
            isInput: hasInput,
            isOutput: hasOutput,
            channels: max(outputChannels, hasOutput ? 2 : 0),
            inputChannels: max(inputChannels, hasInput ? 1 : 0)
        )
    }

    private func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let bufferListPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(dataSize))
        defer { bufferListPtr.deallocate() }
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPtr)
        guard status == noErr else { return 0 }

        return bufferListPtr.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        }
    }

    // MARK: - Sample rate

    func availableSampleRates(for deviceID: AudioDeviceID) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return [44_100, 48_000, 88_200, 96_000]
        }
        let count = Int(dataSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &ranges) == noErr else {
            return [44_100, 48_000, 88_200, 96_000]
        }

        var rates = Set<Double>()
        for range in ranges {
            // Discrete rates usually have mMinimum == mMaximum
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                for candidate in [44_100.0, 48_000.0, 88_200.0, 96_000.0, 176_400.0, 192_000.0] {
                    if candidate >= range.mMinimum && candidate <= range.mMaximum {
                        rates.insert(candidate)
                    }
                }
            }
        }
        let sorted = rates.sorted()
        return sorted.isEmpty ? [44_100, 48_000, 88_200, 96_000] : sorted
    }

    func nominalSampleRate(for deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        return status == noErr ? rate : 0
    }

    func setNominalSampleRate(_ rate: Double, for deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float64(rate)
        let size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw NSError(
                domain: "AudioDeviceManager",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Could not set sample rate to \(Int(rate)) Hz (OSStatus \(status))."]
            )
        }
    }

    func bufferFrameSize(for deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &frames)
        return status == noErr ? frames : nil
    }
    
    private func getDefaultInputDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        guard status == noErr else { return nil }
        
        if let device = getDeviceInfo(deviceID: deviceID), device.isInput {
            return AudioDevice(
                id: deviceID,
                name: "\(device.name) (Default)",
                isInput: true,
                isOutput: device.isOutput,
                channels: device.channels,
                inputChannels: device.inputChannels
            )
        }
        
        return nil
    }
    
    private func getDefaultOutputDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        guard status == noErr else { return nil }
        
        if let device = getDeviceInfo(deviceID: deviceID), device.isOutput {
            return AudioDevice(
                id: deviceID,
                name: "\(device.name) (Default)",
                isInput: device.isInput,
                isOutput: true,
                channels: device.channels,
                inputChannels: device.inputChannels
            )
        }
        
        return nil
    }
}

