import AppKit
import Carbon
import Combine
import CoreBluetooth

struct EdgeDisplay: Identifiable, Equatable {
    let id: String
    let name: String
    let bounds: CGRect
}

@MainActor
final class EdgeSwitchCoordinator: ObservableObject {
    let directInput = DirectInputController()
    private let lowEnergy: HIDPeripheral
    private let central: HIDCentral
    private let cursor = CursorConcealer()
    private lazy var tap = InputTap { [weak self] event in self?._receive(event) }
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var subscriptions = Set<AnyCancellable>()
    private var tapReady = false
    private var tapStarting = false
    private var currentTarget: UUID?
    private var captureTarget: UUID?
    private var restoringPreferences = true

    @Published private(set) var isRemote = false
    @Published private(set) var targetAvailable = false
    @Published private(set) var permissionGranted = false
    @Published private(set) var secureInput = false
    @Published private(set) var displays: [EdgeDisplay] = []
    @Published private(set) var lastError: String?
    @Published var edgeEnabled = false {
        didSet { _save() }
    }

    @Published var displayID = "" {
        didSet { _save() }
    }

    @Published var edge: DisplayEdge = .right {
        didSet { _save() }
    }

    @Published var switchDelay = AppSettings.defaultSwitchDelay {
        didSet { _save() }
    }

    @Published var cornerSize = AppSettings.defaultCornerSize {
        didSet { _save() }
    }

    var recordingShortcut = false {
        didSet { _configure() }
    }

    @Published var locked = false {
        didSet { _configure() }
    }

    @Published var shortcut = ToggleShortcut() {
        didSet { _save() }
    }

    init(lowEnergy: HIDPeripheral, central: HIDCentral) {
        self.lowEnergy = lowEnergy
        self.central = central
        let defaults = UserDefaults.standard
        edgeEnabled = defaults.bool(forKey: AppSettings.edgeSwitchEnabledKey)
        displayID = defaults.string(forKey: AppSettings.edgeDisplayUUIDKey) ?? ""
        edge = DisplayEdge(rawValue: defaults.string(forKey: AppSettings.edgeSideKey) ?? "") ?? .right
        switchDelay = defaults.object(forKey: AppSettings.switchDelayMsKey) as? Double ?? AppSettings.defaultSwitchDelay
        cornerSize = defaults.object(forKey: AppSettings.cornerSizePxKey) as? Double ?? AppSettings.defaultCornerSize
        shortcut = ToggleShortcut(
            keyCode: UInt16(clamping: defaults.object(forKey: AppSettings.toggleKeyCodeKey) as? Int ?? 53),
            modifiers: UInt64(defaults
                .object(forKey: AppSettings.toggleModifiersKey) as? Int ?? Int(CGEventFlags.maskSecondaryFn.rawValue)),
            enabled: defaults.object(forKey: AppSettings.toggleHotkeyEnabledKey) as? Bool ?? true
        )
        restoringPreferences = false
    }

    func start() {
        guard timer == nil else { return }
        _refreshDisplays()
        lowEnergy.start()
        central.start()
        lowEnergy.$subscribedCentrals.combineLatest(lowEnergy.$inactiveCentrals, lowEnergy.$state)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?._refresh() }
            }.store(in: &subscriptions)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.returnLocal()
                self?._refreshDisplays()
            }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.returnLocal() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?._refresh() }
        }
        _refresh()
    }

    func stop() {
        returnLocal()
        timer?.invalidate()
        timer = nil
        tap.stop()
        tapReady = false
        tapStarting = false
    }

    func toggle() {
        guard permissionGranted else { AccessibilityPermission.request(); return }
        guard tapReady, isRemote || targetAvailable, !secureInput else { return }
        tap.requestToggle()
    }

    func returnLocal() {
        tap.forceLocal()
        cursor.restore()
        directInput.stop()
        isRemote = false
        captureTarget = nil
    }

    var shortcutLabel: String {
        guard shortcut.enabled else { return L10n.Layout.disabledString }
        let flags = CGEventFlags(rawValue: shortcut.modifiers)
        var label = ""
        if flags.contains(.maskControl) { label += "⌃" }
        if flags.contains(.maskAlternate) { label += "⌥" }
        if flags.contains(.maskShift) { label += "⇧" }
        if flags.contains(.maskCommand) { label += "⌘" }
        if flags.contains(.maskSecondaryFn) { label += "fn " }
        return label + (shortcut.keyCode == 53 ? "⎋" : L10n.Layout.keyCodeString(shortcut.keyCode))
    }

    private var geometry: EdgeGeometry? {
        guard let display = displays.first(where: { $0.id == displayID }) else { return nil }
        return EdgeGeometry(
            bounds: display.bounds, edge: edge, otherDisplays: displays.filter { $0.id != displayID }.map(\.bounds),
            cornerSize: max(0, cornerSize)
        )
    }

    private func _refreshDisplays() {
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return EdgeDisplay(id: CFUUIDCreateString(nil, uuid) as String, name: screen.localizedName, bounds: CGDisplayBounds(id))
        }
        if displayID.isEmpty { displayID = displays.first?.id ?? "" }
        _configure()
    }

    private func _refresh() {
        permissionGranted = AccessibilityPermission.isTrusted && CGPreflightPostEventAccess()
        secureInput = IsSecureEventInputEnabled()
        let candidates = lowEnergy.subscribedCentrals.filter { id, characteristics in
            !lowEnergy.inactiveCentrals.contains(id) && (
                characteristics.contains(HIDProfile.report) ||
                    (characteristics.contains(HIDProfile.bootMouseInputReport) && characteristics
                        .contains(HIDProfile.bootKeyboardInputReport))
            )
        }.map(\.key)
        currentTarget = candidates.count == 1 && lowEnergy.state == .poweredOn ? candidates.first : nil
        targetAvailable = currentTarget != nil
        if isRemote, !permissionGranted || secureInput || captureTarget != currentTarget || geometry == nil { returnLocal() }
        if permissionGranted, !tapReady, !tapStarting {
            tapStarting = true
            tap.start()
        }
        _configure()
    }

    private func _configure() {
        tap.configure(TapConfiguration(
            targetAvailable: targetAvailable && permissionGranted && !secureInput,
            edgeEnabled: edgeEnabled && !locked && !recordingShortcut,
            geometry: geometry,
            delay: max(0, switchDelay) / 1000,
            shortcut: recordingShortcut ? ToggleShortcut(enabled: false) : shortcut
        ))
    }

    private func _save() {
        guard !restoringPreferences else { return }
        if isRemote { returnLocal() }
        let defaults = UserDefaults.standard
        defaults.set(edgeEnabled, forKey: AppSettings.edgeSwitchEnabledKey)
        defaults.set(displayID, forKey: AppSettings.edgeDisplayUUIDKey)
        defaults.set(edge.rawValue, forKey: AppSettings.edgeSideKey)
        defaults.set(switchDelay, forKey: AppSettings.switchDelayMsKey)
        defaults.set(cornerSize, forKey: AppSettings.cornerSizePxKey)
        defaults.set(Int(shortcut.keyCode), forKey: AppSettings.toggleKeyCodeKey)
        defaults.set(Int(shortcut.modifiers), forKey: AppSettings.toggleModifiersKey)
        defaults.set(shortcut.enabled, forKey: AppSettings.toggleHotkeyEnabledKey)
        _configure()
    }

    private func _receive(_ event: TapOutput) {
        switch event {
        case let .installed(success):
            tapStarting = false
            tapReady = success
            if !success { lastError = L10n.DirectInput.captureFailedString }
        case let .begin(generation, origin):
            guard tap.isCurrent(generation) else { return }
            guard targetAvailable, permissionGranted, !IsSecureEventInputEnabled(),
                  let geometry else { returnLocal(); return }
            guard cursor.hide(at: geometry.parkingPoint, returningTo: origin) else {
                lastError = L10n.Layout.cursorFailedString
                returnLocal()
                return
            }
            lastError = nil
            captureTarget = currentTarget
            directInput.start(HIDInput.make(lowEnergy: lowEnergy, central: central))
            isRemote = true
        case let .input(generation, input):
            guard tap.isCurrent(generation), isRemote else { return }
            directInput.handle(input)
        case let .end(generation):
            if tap.isCurrent(generation) { returnLocal() }
        case .disabled:
            returnLocal()
            tap.reenable()
        }
    }
}
