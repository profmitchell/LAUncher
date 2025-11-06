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
    private var connectedSource: MidiSource?
    private var endpointCache: [MIDIUniqueID: MIDIEndpointRef] = [:]

    init() {
        setupMIDIClient()
        refreshSources()
        if let first = availableSources.first {
            selectedSource = first
        }
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

        if let connected = connectedSource, connected != selectedSource {
            if let endpoint = endpointCache[connected.id] {
                MIDIPortDisconnectSource(inputPort, endpoint)
            }
            connectedSource = nil
        }

        guard let selectedSource, selectedSource != connectedSource else {
            return
        }

        guard let endpoint = endpointCache[selectedSource.id] else { return }

        let result = MIDIPortConnectSource(inputPort, endpoint, nil)
        if result == noErr {
            connectedSource = selectedSource
        }
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        guard let source = connectedSource else { return }

        let numPackets = Int(packetList.pointee.numPackets)
        let listPointer = UnsafeMutablePointer(mutating: packetList)

        var packetPointer = withUnsafeMutablePointer(to: &listPointer.pointee.packet) { $0 }

        for _ in 0..<numPackets {
            let packet = packetPointer.pointee
            let byteCount = Int(packet.length)

            let bytes = withUnsafeBytes(of: packet.data) { rawBuffer -> [UInt8] in
                Array(rawBuffer.prefix(byteCount))
            }

            if bytes.count >= 3 {
                let event = MidiEvent(
                    timestamp: packet.timeStamp,
                    source: source,
                    statusByte: bytes[0],
                    data1: bytes[1],
                    data2: bytes[2]
                )
                Task { @MainActor in
                    self.eventHandler?(event)
                }
            }

            packetPointer = MIDIPacketNext(packetPointer)
        }
    }
}
