import CoreGraphics
import Foundation

struct TapConfiguration: Equatable, Sendable {
    var targetAvailable = false
    var edgeEnabled = false
    var geometry: EdgeGeometry?
    var delay: Double = 0.25
    var shortcut = ToggleShortcut()
}

enum TapOutput: Sendable {
    case installed(Bool)
    case begin(Int, CGPoint)
    case input(Int, DirectInputEvent)
    case end(Int)
    case disabled
}

/// all mutable tap state is protected by lock; the callback decides routing synchronously
final class InputTap: @unchecked Sendable {
    private let lock = NSLock()
    private var configuration = TapConfiguration()
    private var handoff = HandoffState()
    private var remote = false
    private var generation = 0
    private var edgeSince: TimeInterval?
    private var location = CGPoint.zero
    private var dropNextMotion = false
    private var eventTap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var running = false
    private let output: @MainActor @Sendable (TapOutput) -> Void

    init(output: @escaping @MainActor @Sendable (TapOutput) -> Void) {
        self.output = output
    }

    func configure(_ value: TapConfiguration) {
        lock.withLock {
            guard configuration != value else { return }
            configuration = value
            edgeSince = nil
            handoff.cancel()
        }
    }

    func start() {
        let shouldStart = lock.withLock {
            guard !running else { return false }
            running = true
            return true
        }
        guard shouldStart else { return }
        Thread { [self] in _run() }.start()
    }

    func stop() {
        lock.withLock {
            running = false
            remote = false
            generation += 1
            if let eventTap { CFMachPortInvalidate(eventTap) }
            if let runLoop { CFRunLoopStop(runLoop) }
        }
    }

    func reenable() {
        lock.withLock {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        }
    }

    func requestToggle() {
        lock.withLock { handoff.requestToggle() }
    }

    func forceLocal() {
        lock.withLock {
            remote = false
            generation += 1
            handoff.cancel()
            edgeSince = nil
            dropNextMotion = true
        }
    }

    func isCurrent(_ value: Int) -> Bool {
        lock.withLock { generation == value }
    }

    private func _emit(_ event: TapOutput) {
        let output = output
        DispatchQueue.main.async { output(event) }
    }

    private func _run() {
        let mask = [
            CGEventType.keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseUp,
            .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel
        ].reduce(CGEventMask(0)) { $0 | CGEventMask(1) << CGEventMask($1.rawValue) }
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Self.callback, userInfo: refcon
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            lock.withLock { running = false }
            _emit(.installed(false))
            return
        }
        let loop = CFRunLoopGetCurrent()!
        lock.withLock {
            eventTap = tap
            runLoop = loop
            handoff.heldKeys = Set((0 ... 127).compactMap { code in
                CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)) ? UInt16(code) : nil
            })
            location = CGEvent(source: nil)?.location ?? .zero
            handoff.heldKeys.remove(57)
            handoff.modifiers = CGEventSource.flagsState(.combinedSessionState)
            handoff.heldButtons = Set((0 ... 31).compactMap { button in
                guard let cgButton = CGMouseButton(rawValue: UInt32(button)) else { return nil }
                return CGEventSource.buttonState(.combinedSessionState, button: cgButton) ? Int64(button) : nil
            })
        }
        CFRunLoopAddSource(loop, source, .commonModes)
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.02, 0.02, 0, 0) { [weak self] _ in
            self?._tick()
        }!
        CFRunLoopAddTimer(loop, timer, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        _emit(.installed(true))
        if lock.withLock({ running }) { CFRunLoopRun() }
        CFRunLoopTimerInvalidate(timer)
        CFMachPortInvalidate(tap)
        lock.withLock {
            eventTap = nil
            runLoop = nil
        }
    }

    private func _tick() {
        lock.withLock {
            guard running else { return }
            // the last local key-up has returned from its callback before this timer can commit
            if handoff.takeToggle() {
                if remote { _end() } else if configuration.targetAvailable { _begin() }
                return
            }
            guard !remote, configuration.targetAvailable, configuration.edgeEnabled,
                  let geometry = configuration.geometry, let edgeSince,
                  geometry.isAtEdge(location), handoff.isReleased,
                  ProcessInfo.processInfo.systemUptime - edgeSince >= configuration.delay else { return }
            _begin(fromEdge: true)
        }
    }

    private func _begin(fromEdge: Bool = false) {
        guard let geometry = configuration.geometry else { return }
        remote = true
        generation += 1
        edgeSince = nil
        dropNextMotion = true
        // placement and panel ownership stay on the main actor; input is already suppressed here
        _emit(.begin(generation, fromEdge ? geometry.inset(location) : location))
    }

    private func _end() {
        remote = false
        edgeSince = nil
        dropNextMotion = true
        _emit(.end(generation))
    }

    private func _handle(type: CGEventType, event: CGEvent) -> Bool {
        lock.withLock {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                remote = false
                generation += 1
                edgeSince = nil
                handoff.cancel()
                _emit(.disabled)
                return false
            }
            handoff.modifiers = event.flags
            let wasRemote = remote
            if type == .keyDown || type == .keyUp {
                let consumed = handoff.key(
                    code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), down: type == .keyDown,
                    repeatEvent: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                    flags: event.flags,
                    shortcut: remote || configuration.targetAvailable ? configuration.shortcut : ToggleShortcut(enabled: false)
                )
                if consumed { return true }
            } else if type == .flagsChanged {
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                if code != 57, CGEventSource.keyState(.combinedSessionState, key: code) {
                    handoff.heldKeys.insert(code)
                } else { handoff.heldKeys.remove(code) }
            }
            _trackButtons(type: type, event: event)
            let motion = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type)
            if !remote {
                location = event.location
                if motion, dropNextMotion {
                    dropNextMotion = false
                    edgeSince = nil
                } else if motion { _checkEdge(event) }
            } else if motion {
                if let point = configuration.geometry?.parkingPoint { CGWarpMouseCursorPosition(point) }
                if dropNextMotion {
                    dropNextMotion = false
                    return true
                }
            }
            if wasRemote, let input = DirectInputEvent(type: type, event: event) {
                _emit(.input(generation, input))
            }
            return wasRemote
        }
    }

    private func _trackButtons(type: CGEventType, event: CGEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            handoff.heldButtons.insert(event.getIntegerValueField(.mouseEventButtonNumber))
        } else if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(type) {
            handoff.heldButtons.remove(event.getIntegerValueField(.mouseEventButtonNumber))
        }
    }

    private func _checkEdge(_ event: CGEvent) {
        guard configuration.edgeEnabled, configuration.targetAvailable,
              let geometry = configuration.geometry, geometry.isAtEdge(location)
        else {
            edgeSince = nil
            return
        }
        let dx = event.getIntegerValueField(.mouseEventDeltaX)
        let dy = event.getIntegerValueField(.mouseEventDeltaY)
        // arrival plus dwell also works on systems that stop reporting outward deltas at the edge
        if geometry.isOutward(dx: dx, dy: dy) || (dx == 0 && dy == 0) {
            if edgeSince == nil { edgeSince = ProcessInfo.processInfo.systemUptime }
        } else { edgeSince = nil }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<InputTap>.fromOpaque(userInfo).takeUnretainedValue()
        return owner._handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }
}
