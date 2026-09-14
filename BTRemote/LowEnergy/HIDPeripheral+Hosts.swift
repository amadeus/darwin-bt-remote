import CoreBluetooth
import Foundation

/// Allowed-host selection and advertising share one readiness decision.
extension HIDPeripheral {
    static let emptyReports: [UInt8: Data] = [
        ReportID.mouse.rawValue: MouseReport.zero.data,
        ReportID.keyboard.rawValue: KeyboardReport.zero.data,
        ReportID.systemControl.rawValue: SystemControlReport.zero.data,
        ReportID.consumerControl.rawValue: ConsumerReport.zero.data
    ]

    func setAllowed(_ id: UUID, _ allowed: Bool) {
        var policy = hostPolicy
        if allowed { policy.allowed.insert(id) } else { policy.allowed.remove(id) }
        policy.reconcile(ready: hostPolicy.ready)
        apply(policy)
        UserDefaults.standard.set(policy.allowed.map(\.uuidString).sorted(), forKey: AppSettings.allowedHostsKey)
    }

    func selectHost(_ id: UUID) {
        var policy = hostPolicy
        policy.select(id)
        apply(policy)
    }

    func clearAllowedHosts() {
        var policy = hostPolicy
        policy.allowed.removeAll()
        policy.reconcile(ready: policy.ready)
        apply(policy)
        UserDefaults.standard.removeObject(forKey: AppSettings.allowedHostsKey)
    }

    func reconcileHosts() {
        var policy = hostPolicy
        policy.reconcile(ready: Set(inputSubscriptions.compactMap { id, inputs in
            HIDHostPolicy.inputReady(inputs) ? id : nil
        }))
        apply(policy)
    }

    func reconcileAdvertising() {
        guard let pManager else { return }
        let wanted = isHIDServiceAllowed && state == .poweredOn && isHIDServiceAdded && hostPolicy.needsAdvertising
        if !wanted {
            if isAdvertising || advertisingStarting { pManager.stopAdvertising() }
            advertisingStarting = false
            if isAdvertising { isAdvertising = false }
        } else if !isAdvertising, !advertisingStarting {
            advertisingStarting = true
            pManager.startAdvertising([
                CBAdvertisementDataLocalNameKey: advertiseLocalName,
                CBAdvertisementDataServiceUUIDsKey: [HIDProfile.hidService]
            ])
        }
    }

    func activeRecipients() -> [CBCentral] {
        guard let id = hostPolicy.target, let central = centralObjects[id] else { return [] }
        return [central]
    }

    func inputKind(_ characteristic: CBCharacteristic) -> HIDHostPolicy.Input? {
        if characteristic.uuid == HIDProfile.bootMouseInputReport { return .bootMouse }
        if characteristic.uuid == HIDProfile.bootKeyboardInputReport { return .bootKeyboard }
        switch reportID(forCharacteristic: characteristic) {
        case ReportID.mouse.rawValue: return .mouse
        case ReportID.keyboard.rawValue: return .keyboard
        default: return nil
        }
    }

    func reportID(forCharacteristic char: CBCharacteristic) -> UInt8? {
        for (id, c) in charsByReportID where c.uuid == char.uuid && c === char as AnyObject {
            return id
        }
        // fallback for restored characteristics
        if char.uuid == HIDProfile.report,
           let descriptor = (char as? CBMutableCharacteristic)?
           .descriptors?
           .first(where: { $0.uuid == HIDProfile.reportReference }),
           let value = descriptor.value as? Data,
           let id = value.first
        {
            return id
        }
        return nil
    }
}
