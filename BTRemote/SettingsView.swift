import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var names: DeviceNameStore
    @Environment(\.hid) private var hid
    @State private var showReset = false
    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.useServiceChangedKey) private var forceServiceChanged = true
    @AppStorage(AppSettings.hasSeenWelcomeKey) private var hasSeenWelcome = false

    var body: some View {
        NavigationStack {
            form
                .formStyle(.grouped)
                .navigationTitle(L10n.Tab.settings)
        }
    }

    private var form: some View {
        Form {
            Section(header: Text(L10n.Settings.trackpad)) {
                sensitivityRow(L10n.Settings.trackingSpeed, value: $touchpadSensitivity, range: AppSettings.pointerSensitivityRange)
                sensitivityRow(L10n.Settings.scrollSpeed, value: $scrollSensitivity, range: AppSettings.scrollSensitivityRange)
            }
            Section(footer: Text(L10n.Settings.forceServiceChangedHint)) {
                Toggle(L10n.Settings.forceServiceChanged, isOn: $forceServiceChanged)
                    .onChange(of: forceServiceChanged) {
                        if $0 {
                            lowEnergy.scheduleServiceChanged()
                        }
                    }
            }
            Section(header: Text(L10n.Settings.advanced)) {
                Toggle(L10n.Settings.developerMode, isOn: $developerMode)
                Link(destination: AppSettings.repoURL) {
                    Label(L10n.Settings.sourceCode, systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            if developerMode, hid.isActive {
                batterySection
            }
            resetSection
        }
        .confirmationDialog(L10n.Settings.resetConfirm, isPresented: $showReset, titleVisibility: .visible) {
            Button(L10n.Settings.reset, role: .destructive) { _resetAll() }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) { showReset = true } label: {
                Label(L10n.Settings.reset, systemImage: "trash")
            }
        }
    }

    private func _resetAll() {
        names.clear()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        hasSeenWelcome = false
    }

    private var batterySection: some View {
        Section(header: Text(L10n.Section.battery)) {
            Slider(
                value: Binding(
                    get: { Double(hid.batteryLevel) },
                    set: { hid.updateBattery(UInt8($0)) }
                ),
                in: 0 ... 100,
                step: 1
            )
            HStack {
                Text(L10n.Battery.level)
                Spacer()
                Text(Double(hid.batteryLevel) / 100, format: .percent.precision(.fractionLength(0)))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sensitivityRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .foregroundColor(.secondary)
                    + Text(verbatim: "×").foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: 0.1)
        }
    }
}

#if DEBUG
    #Preview {
        SettingsView()
            .environmentObject(HIDPeripheral())
            .environmentObject(HIDCentral())
            .environmentObject(DeviceNameStore())
            .environmentObject(HIDClassicDevice())
    }
#endif
