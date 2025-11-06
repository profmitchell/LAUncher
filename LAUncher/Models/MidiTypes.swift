import CoreMIDI

struct MidiSource: Identifiable, Equatable, Hashable {
    let id: MIDIUniqueID
    let name: String
}

struct MidiEvent: Identifiable {
    enum MessageType {
        case noteOn
        case noteOff
        case controlChange
        case other
    }

    let id = UUID()
    let timestamp: MIDITimeStamp
    let source: MidiSource?
    let statusByte: UInt8
    let data1: UInt8
    let data2: UInt8

    var channel: UInt8 { statusByte & 0x0F }

    var messageType: MessageType {
        switch statusByte & 0xF0 {
        case 0x80: return .noteOff
        case 0x90: return data2 == 0 ? .noteOff : .noteOn
        case 0xB0: return .controlChange
        default: return .other
        }
    }
}
