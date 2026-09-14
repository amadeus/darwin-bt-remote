import CoreBluetooth
import Foundation
import os

@MainActor
final class CompanionService: ObservableObject {
    nonisolated(unsafe) static let uuid = CBUUID(string: "d5df0001-fd35-4b5c-8fc9-39dd1c43cb1d")
    @Published private(set) var ready: Set<UUID> = []
    @Published private(set) var monitors: [UUID: [PCMonitor]] = [:]
    @Published private(set) var blind: [UUID: UInt8] = [:]
    private(set) var lastSeen: [UUID: TimeInterval] = [:]
    var onLeave: ((UUID, UInt8, UInt8, UInt16) -> Void)?
    var clipboardTarget: (() -> UUID?)?
    var onClipboard: ((UUID, CompanionProtocol.Message, Data) throws -> Void)?
    var onReady: ((UUID) -> Void)?
    private var manager: CBPeripheralManager?
    private var clients: [UUID: Client] = [:]
    private var controls: [Queued] = []
    private var bulk: [Queued] = []
    private var blocked = false
    private var enabled = true
    private var chars: [CBMutableCharacteristic] = []
    var diagnosticState: String {
        "queued=\(controls.count + bulk.count) blocked=\(blocked)"
    }

    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "Companion")

    private struct Client {
        let central: CBCentral
        var subscriptions: Set<Int> = []
        var controlEncoder = CompanionProtocol.Encoder()
        var bulkEncoder = CompanionProtocol.Encoder()
        var controlDecoder = CompanionProtocol.Decoder()
        var bulkDecoder = CompanionProtocol.Decoder()
        var helloSent = false
        var supportsResume = false
        var supportsCenter = false
        var supportsClipboard = false
    }

    private struct Queued { let data: Data; let index: Int; let central: CBCentral }

    func build(_ manager: CBPeripheralManager) -> CBMutableService {
        reset()
        self.manager = manager
        let service = CBMutableService(type: Self.uuid, primary: true)
        let properties: [CBCharacteristicProperties] = [
            .notifyEncryptionRequired,
            .writeWithoutResponse,
            .notifyEncryptionRequired,
            .write,
            .read
        ]
        chars = (0 ..< 5).map { index in
            CBMutableCharacteristic(
                type: CBUUID(string: String(format: "d5df%04x-fd35-4b5c-8fc9-39dd1c43cb1d", index + 2)),
                properties: properties[index], value: nil,
                permissions: index == 1 || index == 3 ? .writeEncryptionRequired : .readEncryptionRequired
            )
        }
        service.characteristics = chars
        return service
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value {
            clients.removeAll(); ready.removeAll(); monitors.removeAll(); blind.removeAll(); lastSeen.removeAll()
            controls.removeAll(); bulk.removeAll()
        }
    }

    func reset() {
        clients.removeAll(); ready.removeAll(); monitors.removeAll(); blind.removeAll(); lastSeen.removeAll()
        controls.removeAll(); bulk.removeAll(); chars.removeAll(); blocked = false; manager = nil
    }

    func owns(_ characteristic: CBCharacteristic) -> Bool {
        chars.contains { $0.uuid == characteristic.uuid }
    }

    func subscribed(_ central: CBCentral, _ characteristic: CBCharacteristic) {
        guard enabled else { return }
        guard let index = chars.firstIndex(where: { $0.uuid == characteristic.uuid }) else { return }
        var client = clients[central.identifier] ?? Client(central: central)
        client.subscriptions.insert(index)
        let sendHello = client.subscriptions.contains(0) && client.subscriptions.contains(2) && !client.helloSent
        client.helloSent = client.helloSent || sendHello
        clients[central.identifier] = client
        if sendHello {
            sendJSON(CompanionHello(v: 1, role: "mac", name: "BTRemote", chunk: 20, clipboard: 1), type: .hello, to: central.identifier)
        }
    }

    func unsubscribed(_ central: CBCentral) {
        disconnect(central.identifier)
    }

    private func disconnect(_ id: UUID) {
        if ready.contains(id) { log.notice("companion disconnected") }
        clients.removeValue(forKey: id); ready.remove(id); monitors.removeValue(forKey: id)
        blind.removeValue(forKey: id); lastSeen.removeValue(forKey: id)
        controls.removeAll { $0.central.identifier == id }; bulk.removeAll { $0.central.identifier == id }
    }

    func receive(_ request: CBATTRequest) -> CBATTError.Code {
        guard enabled, request.offset == 0, let value = request.value,
              let index = chars.firstIndex(where: { $0.uuid == request.characteristic.uuid }),
              index == 1 || index == 3, var client = clients[request.central.identifier] else { return .writeNotPermitted }
        do {
            let packet = try index == 1 ? client.controlDecoder.receive(value) : client.bulkDecoder.receive(value)
            clients[request.central.identifier] = client
            if let packet {
                guard packet.stream == (index == 1 ? 0 : 1) else { throw CompanionProtocol.Failure.malformed }
                try handle(packet, from: request.central.identifier)
            }
            return .success
        } catch {
            log.error("invalid companion message: \(String(describing: error), privacy: .public)")
            disconnect(request.central.identifier)
            return .unlikelyError
        }
    }

    func respond(to request: CBATTRequest, using manager: CBPeripheralManager) {
        let value = Data("{\"v\":1,\"ready\":\(ready.contains(request.central.identifier))}".utf8)
        guard request.offset <= value.count else { manager.respond(to: request, withResult: .invalidOffset); return }
        request.value = Data(value.dropFirst(request.offset))
        manager.respond(to: request, withResult: .success)
    }

    private func handle(_ packet: CompanionProtocol.Packet, from id: UUID) throws {
        guard let type = CompanionProtocol.Message(rawValue: packet.type) else { throw CompanionProtocol.Failure.malformed }
        if type == .hello {
            try receiveHello(packet.payload, from: id)
            return
        }
        guard ready.contains(id) else { throw CompanionProtocol.Failure.malformed }
        lastSeen[id] = ProcessInfo.processInfo.systemUptime
        if [.clipGrab, .clipGet, .clipData, .clipState].contains(type) {
            try receiveClipboard(packet, type: type, from: id)
            return
        }
        switch type {
        case .screens:
            try receiveScreens(packet.payload, from: id)
        case .ping:
            guard packet.payload.count == 4 else { throw CompanionProtocol.Failure.malformed }
            send(.pong, payload: packet.payload, to: id)
        case .state:
            guard packet.payload.count == 3 else { throw CompanionProtocol.Failure.malformed }
            blind[id] = packet.payload[0]
        case .leave:
            guard packet.payload.count == 4, packet.payload[1] < 4 else { throw CompanionProtocol.Failure.malformed }
            let frac = UInt16(packet.payload[2]) | UInt16(packet.payload[3]) << 8
            onLeave?(id, packet.payload[0], packet.payload[1], frac)
        case .enterAck:
            guard packet.payload.count == 7 else { throw CompanionProtocol.Failure.malformed }
            blind[id] = packet.payload[6]
        case .pong: break
        default: throw CompanionProtocol.Failure.malformed
        }
    }

    private func receiveClipboard(_ packet: CompanionProtocol.Packet, type: CompanionProtocol.Message, from id: UUID) throws {
        guard clipboardTarget?() == id else { return }
        guard supportsClipboard(id), packet.stream == (type == .clipData ? 1 : 0) else {
            throw CompanionProtocol.Failure.malformed
        }
        try onClipboard?(id, type, packet.payload)
    }

    private func receiveHello(_ data: Data, from id: UUID) throws {
        let hello = try JSONDecoder().decode(CompanionHello.self, from: data)
        guard hello.v == 1, hello.role == "pc", hello.chunk >= 20,
              clients[id]?.helloSent == true else { throw CompanionProtocol.Failure.malformed }
        clients[id]?.supportsResume = hello.resume == true
        clients[id]?.supportsCenter = hello.center == true
        clients[id]?.supportsClipboard = hello.clipboard == 1
        ready.insert(id)
        lastSeen[id] = ProcessInfo.processInfo.systemUptime
        onReady?(id)
        log.info("Windows companion handshake complete")
    }

    private func receiveScreens(_ data: Data, from id: UUID) throws {
        let screens = try JSONDecoder().decode(PCScreenInfo.self, from: data).monitors
        guard screens.count <= 32, screens.allSatisfy({ $0.w > 4 && $0.h > 4 && $0.w <= 32768 && $0.h <= 32768 }),
              Set(screens.map(\.id)).count == screens.count else { throw CompanionProtocol.Failure.malformed }
        monitors[id] = screens
        onReady?(id)
    }

    func supportsResume(_ id: UUID) -> Bool {
        ready.contains(id) && clients[id]?.supportsResume == true
    }

    func supportsCenter(_ id: UUID) -> Bool {
        ready.contains(id) && clients[id]?.supportsCenter == true
    }

    func supportsClipboard(_ id: UUID) -> Bool {
        ready.contains(id) && clients[id]?.supportsClipboard == true
    }

    func sendClipboard(_ type: CompanionProtocol.Message, payload: Data, to id: UUID) {
        guard clipboardTarget?() == id, supportsClipboard(id), payload.count <= ClipboardTransfer.blockBytes + 12 else { return }
        if type == .clipData {
            enqueue(type, stream: 1, payload: payload, to: id)
        } else {
            send(type, payload: payload, to: id)
        }
    }

    func sendJSON(_ value: some Encodable, type: CompanionProtocol.Message, to id: UUID) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        enqueue(type, stream: 1, payload: data, to: id)
    }

    func send(_ type: CompanionProtocol.Message, payload: Data, to id: UUID) {
        guard ready.contains(id), payload.count <= 13 else { return }
        enqueue(type, stream: 0, payload: payload, to: id)
    }

    private func enqueue(_ type: CompanionProtocol.Message, stream: UInt8, payload: Data, to id: UUID) {
        guard enabled, var client = clients[id], payload.count <= CompanionProtocol.maximumPayload else { return }
        let packet = CompanionProtocol.Packet(stream: stream, type: type.rawValue, payload: payload)
        let frames = stream == 0 ? client.controlEncoder.encode(packet) : client.bulkEncoder.encode(packet)
        clients[id] = client
        guard controls.count + bulk.count + frames.count <= 512 else { disconnect(id); return }
        let items = frames.map { Queued(data: $0, index: stream == 0 ? 0 : 2, central: client.central) }
        if stream == 0 { controls.append(contentsOf: items) } else { bulk.append(contentsOf: items) }
        drain()
    }

    func readyToSend() {
        blocked = false; drain()
    }

    private func drain() {
        guard enabled, let manager, !blocked else { return }
        while let item = controls.first ?? bulk.first {
            guard manager.updateValue(item.data, for: chars[item.index], onSubscribedCentrals: [item.central]) else {
                blocked = true
                return
            }
            if !controls.isEmpty { controls.removeFirst() } else { bulk.removeFirst() }
        }
    }
}
