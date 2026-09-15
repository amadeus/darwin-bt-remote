import AppKit

@MainActor
final class MacClipboardSync {
    private let service: CompanionService
    private let transfer = ClipboardTransfer()
    private var target: UUID?
    private var epoch: UInt32 = 0
    private var generation: UInt64 = 0
    private var peerAvailable = false
    private var enabled = false
    private var primed = false
    private var preference = true
    private var awake = true
    private var available = true
    private var remote = false
    private var revision = 0
    private var observers: [NSObjectProtocol] = []
    private lazy var pasteboard = ClipboardPasteboard(snapshot: { [weak self] snapshot in
        DispatchQueue.main.async { [weak self] in self?.observe(snapshot) }
    }, yielded: { [weak self] epoch, generation in
        DispatchQueue.main.async { [weak self] in self?.yield(epoch, generation: generation) }
    })

    private func observe(_ snapshot: ClipboardPasteboard.Snapshot) {
        guard enabled, snapshot.epoch == epoch, snapshot.generation == generation else { return }
        revision = snapshot.revision
        transfer.observe(snapshot.text, announce: snapshot.announce)
        if !primed {
            primed = true
            if let target { acknowledge(target, enabled: true) }
        }
    }

    private func yield(_ epoch: UInt32, generation: UInt64) {
        guard enabled, self.epoch == epoch, self.generation == generation else { return }
        transfer.yield()
    }

    init(service: CompanionService) {
        self.service = service
        transfer.send = { [weak self] type, data in
            guard let self, enabled, let target else { return }
            service.sendClipboard(type, payload: data, to: target)
        }
        transfer.apply = { [weak self] data in
            guard let self, enabled else { return }
            pasteboard.write(data, epoch: epoch, revision: revision)
        }
        service.onClipboard = { [weak self] id, type, data in try self?.receive(id, type: type, data: data) }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setAwake(false) }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setAwake(true) }
            })
        }
    }

    func update(target: UUID?, remote: Bool, enabled: Bool, available: Bool) {
        let next = target.flatMap { service.supportsClipboard($0) ? $0 : nil }
        if self.target != next {
            if let old = self.target { acknowledge(old, enabled: false) }
            self.target = next; peerAvailable = false; self.enabled = false; epoch = 0
            transfer.reset(0); generation = pasteboard.configure(epoch: 0, enabled: false)
        }
        let entering = !self.remote && remote
        self.remote = remote; preference = enabled; self.available = available
        reconcile()
        transfer.setActive(!remote, now: ProcessInfo.processInfo.systemUptime)
        if entering, self.enabled { pasteboard.yield() }
        if self.enabled { transfer.tick(ProcessInfo.processInfo.systemUptime) }
    }

    func stop() {
        preference = false; reconcile()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func setAwake(_ value: Bool) {
        awake = value; reconcile()
    }

    private func reconcile() {
        let wanted = target != nil && preference && available && awake && peerAvailable
        guard wanted != enabled else { return }
        enabled = wanted; primed = false; transfer.reset(epoch); generation = pasteboard.configure(epoch: epoch, enabled: wanted)
        if !wanted, let target { acknowledge(target, enabled: false) }
        if wanted, remote { pasteboard.yield() }
    }

    private func acknowledge(_ id: UUID, enabled: Bool) {
        service.sendClipboard(.clipState, payload: CompanionProtocol.u32(epoch) + Data([enabled ? 1 : 0]), to: id)
    }

    private func receive(_ id: UUID, type: CompanionProtocol.Message, data: Data) throws {
        guard target == id else { return }
        if type == .clipState {
            guard data.count == 5, data[4] <= 1 else { throw CompanionProtocol.Failure.malformed }
            let next = CompanionProtocol.read32(data, 0)
            let ready = data[4] == 1
            guard next != epoch || peerAvailable != ready else { return }
            epoch = next; peerAvailable = ready; enabled = false
            transfer.reset(epoch); generation = pasteboard.configure(epoch: epoch, enabled: false)
            reconcile()
            if !enabled { acknowledge(id, enabled: false) }
        } else if enabled, primed {
            try transfer.receive(type, payload: data, now: ProcessInfo.processInfo.systemUptime)
        }
    }
}
