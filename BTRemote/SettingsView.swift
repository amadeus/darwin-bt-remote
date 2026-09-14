import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var names: DeviceNameStore
    @AppStorage(AppSettings.invertVerticalScrollKey) private var invertVerticalScroll = false
    @AppStorage(AppSettings.invertHorizontalScrollKey) private var invertHorizontalScroll = false
    @AppStorage(AppSettings.clipboardEnabledKey) private var clipboardEnabled = true
    @State private var showReset = false
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.useServiceChangedKey) private var forceServiceChanged = true
    @AppStorage(AppSettings.hasSeenWelcomeKey) private var hasSeenWelcome = false

    var body: some View {
        NavigationStack {
            form
                .settingsFormStyle()
                .navigationTitle(L10n.Tab.settings)
        }
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Share text clipboard with Windows", isOn: $clipboardEnabled)
                    .toggleStyle(.switch)
            } footer: {
                Text(
                    "Shares plain text up to 64 KiB. Skips marked private items and pauses while locked or signed out."
                )
            }
            Section("Windows scrolling") {
                Toggle("Invert vertical scrolling", isOn: $invertVerticalScroll)
                    .toggleStyle(.switch)
                Toggle("Invert horizontal scrolling", isOn: $invertHorizontalScroll)
                    .toggleStyle(.switch)
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
        lowEnergy.clearAllowedHosts()
        names.clear()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        hasSeenWelcome = false
    }
}

#if DEBUG
    #Preview {
        SettingsView()
            .environmentObject(HIDPeripheral())
            .environmentObject(HIDCentral())
            .environmentObject(DeviceNameStore())
    }
#endif
