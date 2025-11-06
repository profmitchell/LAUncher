import Foundation
import AVFoundation
import AudioToolbox
import Combine

struct MIDIMapping: Identifiable, Codable, Equatable {
    var id: String { "\(parameterId)_\(ccNumber)" }
    let parameterId: String
    let parameterDisplayName: String
    let ccNumber: UInt8
    let minValue: Float
    let maxValue: Float
    
    static func == (lhs: MIDIMapping, rhs: MIDIMapping) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class MIDIMapManager: ObservableObject {
    @Published var mappings: [MIDIMapping] = []
    @Published var isLearning: Bool = false
    @Published var learningParameterId: String?
    @Published var lastCCReceived: UInt8?
    @Published var isInLearnMode: Bool = false // New: Auto-learn mode
    @Published var pendingCCForLearnMode: UInt8? // CC waiting for next parameter interaction
    
    private var midiEventHandler: ((MidiEvent) -> Void)?
    
    init() {
        loadMappings()
    }
    
    func handleMIDIEvent(_ event: MidiEvent) -> Bool {
        // Check for CC messages (0xB0-0xBF)
        let status = event.statusByte
        let ccStatus: UInt8 = 0xB0
        
        if (status & 0xF0) == ccStatus {
            let ccNumber = event.data1
            let ccValue = event.data2
            
            // Handle learn mode: store CC and wait for parameter interaction
            if isInLearnMode && pendingCCForLearnMode == nil {
                pendingCCForLearnMode = ccNumber
                print("🎹 Learn Mode: Received CC \(ccNumber). Now interact with a parameter to map it.")
                return false // Don't apply yet
            }
            
            if isLearning, let paramId = learningParameterId {
                // Create new mapping
                let mapping = MIDIMapping(
                    parameterId: paramId,
                    parameterDisplayName: "", // Will be set when mapping is confirmed
                    ccNumber: ccNumber,
                    minValue: 0.0,
                    maxValue: 127.0
                )
                mappings.append(mapping)
                isLearning = false
                learningParameterId = nil
                lastCCReceived = ccNumber
                saveMappings()
                return true // Handled
            }
            
            // Apply existing mappings
            if let mapping = mappings.first(where: { $0.ccNumber == ccNumber }) {
                // Convert MIDI CC (0-127) to parameter value (0.0-1.0)
                let normalizedValue = Float(ccValue) / 127.0
                let paramValue = mapping.minValue + (normalizedValue * (mapping.maxValue - mapping.minValue))
                
                // Return true to indicate we handled this, but the actual parameter setting
                // will be done by PluginHostSession
                return false // Let PluginHostSession handle parameter setting
            }
        }
        
        return false // Not handled
    }
    
    func handleParameterInteraction(parameterId: String, parameterDisplayName: String, minValue: Float, maxValue: Float) {
        // If in learn mode and we have a pending CC, create mapping
        if isInLearnMode, let ccNumber = pendingCCForLearnMode {
            let mapping = MIDIMapping(
                parameterId: parameterId,
                parameterDisplayName: parameterDisplayName,
                ccNumber: ccNumber,
                minValue: minValue,
                maxValue: maxValue
            )
            mappings.append(mapping)
            pendingCCForLearnMode = nil
            saveMappings()
            print("✅ Learn Mode: Mapped \(parameterDisplayName) to CC \(ccNumber)")
        }
    }
    
    func toggleLearnMode() {
        isInLearnMode.toggle()
        if !isInLearnMode {
            pendingCCForLearnMode = nil
        }
    }
    
    func createMapping(parameterId: String, parameterDisplayName: String, ccNumber: UInt8, minValue: Float, maxValue: Float) {
        // Check if mapping already exists
        if mappings.contains(where: { $0.parameterId == parameterId && $0.ccNumber == ccNumber }) {
            print("⚠️ Mapping already exists for \(parameterDisplayName) to CC \(ccNumber)")
            return
        }
        
        let mapping = MIDIMapping(
            parameterId: parameterId,
            parameterDisplayName: parameterDisplayName,
            ccNumber: ccNumber,
            minValue: minValue,
            maxValue: maxValue
        )
        mappings.append(mapping)
        saveMappings()
        print("✅ Created mapping: \(parameterDisplayName) → CC \(ccNumber)")
    }
    
    func createMappingsForCC(ccNumber: UInt8, parameterIds: [(id: String, displayName: String, minValue: Float, maxValue: Float)]) {
        for paramInfo in parameterIds {
            createMapping(
                parameterId: paramInfo.id,
                parameterDisplayName: paramInfo.displayName,
                ccNumber: ccNumber,
                minValue: paramInfo.minValue,
                maxValue: paramInfo.maxValue
            )
        }
    }
    
    func getCCValueForParameter(_ parameterId: String, ccValue: UInt8) -> Float? {
        guard let mapping = mappings.first(where: { $0.parameterId == parameterId }) else {
            return nil
        }
        
        let normalizedValue = Float(ccValue) / 127.0
        return mapping.minValue + (normalizedValue * (mapping.maxValue - mapping.minValue))
    }
    
    func startLearning(parameterId: String) {
        isLearning = true
        learningParameterId = parameterId
        lastCCReceived = nil
    }
    
    func cancelLearning() {
        isLearning = false
        learningParameterId = nil
        lastCCReceived = nil
    }
    
    func removeMapping(_ mapping: MIDIMapping) {
        mappings.removeAll { $0.id == mapping.id }
        saveMappings()
    }
    
    func updateMapping(_ mapping: MIDIMapping, minValue: Float, maxValue: Float) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = MIDIMapping(
                parameterId: mapping.parameterId,
                parameterDisplayName: mapping.parameterDisplayName,
                ccNumber: mapping.ccNumber,
                minValue: minValue,
                maxValue: maxValue
            )
            saveMappings()
        }
    }
    
    private func saveMappings() {
        // Ensure directory exists
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let launcherDir = appSupport.appendingPathComponent("LAUncher")
            try? FileManager.default.createDirectory(at: launcherDir, withIntermediateDirectories: true)
            
            let url = launcherDir.appendingPathComponent("midi_mappings.json")
            if let data = try? JSONEncoder().encode(mappings) {
                try? data.write(to: url)
            }
        }
    }
    
    private func loadMappings() {
        guard let url = getMappingsURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([MIDIMapping].self, from: data) else {
            return
        }
        mappings = loaded
    }
    
    private func getMappingsURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LAUncher")
            .appendingPathComponent("midi_mappings.json")
    }
}

