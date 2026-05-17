import Foundation
import CoreMIDI
import Combine

@MainActor
final class MidiManager: ObservableObject {
    @Published private(set) var availableSources: [MidiSource] = []
    @Published var selectedSource: MidiSource? {
        didSet { updateConnection() }
    }

    var eventHandler: ((MidiEvent) -> Void)?

    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var connectedSourceIDs = Set<MIDIUniqueID>()
    private var endpointCache: [MIDIUniqueID: MIDIEndpointRef] = [:]

    init() {
        setupMIDIClient()
        refreshSources()
        if let first = availableSources.first {
            selectedSource = first
        }
        updateConnection()
    }

    func refreshSources() {
        var updatedSources: [MidiSource] = []
        var newCache: [MIDIUniqueID: MIDIEndpointRef] = [:]

        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }

            var uniqueID: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            var nameRef: Unmanaged<CFString>?
            let hasName = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &nameRef) == noErr
            let name = hasName ? (nameRef?.takeRetainedValue() as String? ?? "MIDI Source \(uniqueID)") : "MIDI Source \(uniqueID)"

            let source = MidiSource(id: uniqueID, name: name)
            updatedSources.append(source)
            newCache[uniqueID] = endpoint
        }

        availableSources = updatedSources.sorted { $0.name < $1.name }
        endpointCache = newCache

        if let selected = selectedSource, !availableSources.contains(selected) {
            selectedSource = availableSources.first
        } else {
            updateConnection()
        }
    }

    private func setupMIDIClient() {
        MIDIClientCreateWithBlock("LAUncherMIDIClient" as CFString, &client) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSources()
            }
        }

        MIDIInputPortCreateWithBlock(client, "LAUncherInputPort" as CFString, &inputPort) { [weak self] packetList, _ in
            guard let self else { return }
            self.handle(packetList: packetList)
        }
    }

    private func updateConnection() {
        guard inputPort != 0 else { return }

        for sourceID in connectedSourceIDs {
            if let endpoint = endpointCache[sourceID] {
                MIDIPortDisconnectSource(inputPort, endpoint)
            }
        }
        connectedSourceIDs.removeAll()

        let sourcesToConnect: [MidiSource]
        if let selectedSource {
            sourcesToConnect = [selectedSource]
        } else {
            sourcesToConnect = availableSources
        }

        for source in sourcesToConnect {
            guard let endpoint = endpointCache[source.id] else { continue }
            let result = MIDIPortConnectSource(inputPort, endpoint, nil)
            if result == noErr {
                connectedSourceIDs.insert(source.id)
            }
        }
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        guard !connectedSourceIDs.isEmpty else { return }
        let source = selectedSource

        let numPackets = Int(packetList.pointee.numPackets)
        let listPointer = UnsafeMutablePointer(mutating: packetList)

        var packetPointer = withUnsafeMutablePointer(to: &listPointer.pointee.packet) { $0 }

        for _ in 0..<numPackets {
            let packet = packetPointer.pointee
            let byteCount = Int(packet.length)

            let bytes = withUnsafeBytes(of: packet.data) { rawBuffer -> [UInt8] in
                Array(rawBuffer.prefix(byteCount))
            }

            for message in parseMidiMessages(bytes) {
                let event = MidiEvent(
                    timestamp: packet.timeStamp,
                    source: source,
                    statusByte: message.status,
                    data1: message.data1,
                    data2: message.data2
                )
                Task { @MainActor in
                    self.eventHandler?(event)
                }
            }

            packetPointer = MIDIPacketNext(packetPointer)
        }
    }

    private func parseMidiMessages(_ bytes: [UInt8]) -> [(status: UInt8, data1: UInt8, data2: UInt8)] {
        var messages: [(status: UInt8, data1: UInt8, data2: UInt8)] = []
        var index = 0
        var runningStatus: UInt8?

        while index < bytes.count {
            let byte = bytes[index]
            let status: UInt8

            if byte & 0x80 != 0 {
                status = byte
                runningStatus = status
                index += 1
            } else if let existingStatus = runningStatus {
                status = existingStatus
            } else {
                index += 1
                continue
            }

            let dataLength = midiDataLength(for: status)
            guard dataLength > 0 else { continue }
            guard index + dataLength <= bytes.count else { break }

            let data1 = bytes[index]
            let data2 = dataLength > 1 ? bytes[index + 1] : 0
            messages.append((status, data1, data2))
            index += dataLength
        }

        return messages
    }

    private func midiDataLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0:
            return 1
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
            return 2
        default:
            return 0
        }
    }
}
