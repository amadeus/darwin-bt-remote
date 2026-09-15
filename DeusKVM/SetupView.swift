import AppKit
import CoreBluetooth
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    @EnvironmentObject private var names: DeviceNameStore
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @State private var selectedInfo: DeviceEntry?
    @EnvironmentObject private var coordinator: EdgeSwitchCoordinator

    @Environment(\.hid) private var hid

    var body: some View {
        NavigationStack {
            form
                .settingsFormStyle()
                .navigationTitle(L10n.App.title)
        }
    }

    private var form: some View {
        Form {
            connectionSection
            if !_connectedDevices.isEmpty { connectedDevicesSection }
            statusSection
            if hid.activeError != nil || (hid.isActive && coordinator.lastError != nil) {
                Section(header: Text(L10n.Section.lastError)) {
                    if let lastError = hid.activeError {
                        Text(verbatim: lastError).foregroundColor(.red).font(.caption)
                    }
                    if hid.isActive, let lastError = coordinator.lastError {
                        Text(verbatim: lastError).foregroundColor(.red).font(.caption)
                    }
                }
            }
        }
        .sheet(item: $selectedInfo) { DeviceInfoView(entry: $0) }
    }

    private var statusSection: some View {
        Section(header: Text(L10n.Section.status)) {
            row(L10n.Status.bluetooth, Text(lowEnergy.state.localizedLabel))
            row(L10n.Status.advertising, Text(lowEnergy.isAdvertising ? L10n.Value.yes : L10n.Value.no))
            if developerMode {
                row(L10n.Status.hidService, Text(lowEnergy.isHIDServiceAdded ? L10n.Status.hidServiceAdded : L10n.Value.none))
                row(L10n.Status.subscribedCentrals, Text(lowEnergy.subscribedCentrals.count, format: .number))
                row(L10n.Status.connectedPeripherals, Text(central.connected.count, format: .number))
                row(L10n.Status.hostLEDs, Text(verbatim: lowEnergy.keyboardLEDs.localizedLabel))
            }
        }
    }

    private var connectionSection: some View {
        Section(
            header: Text(L10n.Section.connection),
            footer: Text("Advertising stops when an allowed device is ready and resumes when none is available.")
        ) {
            if lowEnergy.state != .poweredOn {
                Button("Open Bluetooth Settings", action: _openBluetoothSettings)
            } else {
                Text(lowEnergy.hostPolicy.target == nil ? "Waiting for an allowed device" : "Connected to an allowed device")
            }
            Text(
                "Pair through the Windows companion, then turn on Enable control. To replace a PC, turn off its control first."
            )
            .font(.caption).foregroundColor(.secondary)
        }
        .onAppear(perform: _seedAliasesFromScan)
        .onChange(of: lowEnergy.connectedCentrals) { _ in _seedAliasesFromScan() }
        .onChange(of: central.discovered) { _ in _seedAliasesFromScan() }
    }

    private var connectedDevicesSection: some View {
        Section {
            ForEach(_connectedDevices) { connectedDeviceRow($0) }
        } header: {
            Text("Devices")
        } footer: {
            Text(
                "Saved per device. When several enabled devices are ready, choose Use device to select the PC to control."
            )
        }
    }

    /// hosts that connected to us (peripheral role); subscribed ones can receive input
    private var _connectedDevices: [DeviceEntry] {
        lowEnergy.connectedCentrals.union(lowEnergy.hostPolicy.allowed)
            .map { uuid in
                let alias = names.name(for: uuid)
                let subscribed = lowEnergy.subscribedCentrals.keys.contains(uuid)
                return DeviceEntry(
                    id: uuid,
                    name: alias ?? "",
                    isNamed: alias != nil,
                    rssi: 0,
                    advertisedServices: [],
                    companyID: nil,
                    txPower: nil,
                    isConnectable: nil,
                    isHostConnected: lowEnergy.connectedCentrals.contains(uuid),
                    isCentralConnected: false,
                    isConnecting: false,
                    isSubscribed: subscribed,
                    isActive: lowEnergy.hostPolicy.target == uuid
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func _seedAliasesFromScan() {
        for uuid in lowEnergy.connectedCentrals where names.name(for: uuid) == nil {
            guard let scanned = central.discovered.first(where: { $0.id == uuid && $0.isNamed })?.name else { continue }
            names.setName(scanned, for: uuid)
        }
    }

    private func _openBluetoothSettings() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.open(url)
    }

    private func connectedDeviceRow(_ entry: DeviceEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.displayName).lineLimit(1)
                    Text(_deviceStatus(entry)).font(.caption).foregroundColor(.secondary)
                    if developerMode {
                        Text(verbatim: entry.id.uuidString)
                            .font(.caption2).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { selectedInfo = entry } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.DeviceInfo.info)
            }
            Toggle("Enable control", isOn: Binding(
                get: { lowEnergy.hostPolicy.allowed.contains(entry.id) },
                set: { lowEnergy.setAllowed(entry.id, $0) }
            ))
            .toggleStyle(.switch)
            .accessibilityLabel(Text("Enable control: \(entry.displayName)"))
            if lowEnergy.hostPolicy.allowed.contains(entry.id), lowEnergy.hostPolicy.ready.contains(entry.id), !entry.isActive {
                Button("Use device") { lowEnergy.selectHost(entry.id) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func _deviceStatus(_ entry: DeviceEntry) -> String {
        if entry.isActive { return "Current input device" }
        if !entry.isHostConnected { return "Disconnected" }
        if lowEnergy.hostPolicy.ready.contains(entry.id) { return "Ready" }
        return "Waiting for keyboard and mouse"
    }

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(title)
            Spacer()
            value.foregroundColor(.secondary)
        }
    }
}

private extension CBManagerState {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .unknown: return L10n.BluetoothState.unknown
        case .resetting: return L10n.BluetoothState.resetting
        case .unsupported: return L10n.BluetoothState.unsupported
        case .unauthorized: return L10n.BluetoothState.unauthorized
        case .poweredOff: return L10n.BluetoothState.poweredOff
        case .poweredOn: return L10n.BluetoothState.poweredOn
        @unknown default: return L10n.BluetoothState.unavailable
        }
    }
}

private extension KeyboardLEDs {
    var localizedLabel: String {
        var parts: [String] = []
        if contains(.numLock) {
            parts.append(L10n.KeyboardLED.numLock)
        }
        if contains(.capsLock) {
            parts.append(L10n.KeyboardLED.capsLock)
        }
        if contains(.scrollLock) {
            parts.append(L10n.KeyboardLED.scrollLock)
        }
        return parts.isEmpty ? L10n.Value.noneString : ListFormatter.localizedString(byJoining: parts)
    }
}
