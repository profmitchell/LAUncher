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
        
        // Get channel count for output
        var channelCount = 2 // Default to stereo
        if hasOutput {
            propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration
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
                let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
                defer { bufferListPtr.deallocate() }
                status = AudioObjectGetPropertyData(
                    deviceID,
                    &propertyAddress,
                    0,
                    nil,
                    &dataSize,
                    bufferListPtr
                )
                if status == noErr {
                    var totalChannels = 0
                    // Access the first buffer (most devices have one buffer with multiple channels)
                    withUnsafePointer(to: &bufferListPtr.pointee.mBuffers) { buffersPtr in
                        if bufferListPtr.pointee.mNumberBuffers > 0 {
                            totalChannels = Int(buffersPtr.pointee.mNumberChannels)
                        }
                    }
                    channelCount = max(totalChannels, 2)
                }
            }
        }
        
        return AudioDevice(
            id: deviceID,
            name: name,
            isInput: hasInput,
            isOutput: hasOutput,
            channels: channelCount
        )
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
                isOutput: false,
                channels: device.channels
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
                isInput: false,
                isOutput: true,
                channels: device.channels
            )
        }
        
        return nil
    }
}

