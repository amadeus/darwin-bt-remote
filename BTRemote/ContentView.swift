import SwiftUI

struct ContentView: View {
    @State private var tab = Tab.setup

    private enum Tab {
        case setup, layout, remote, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            SetupView()
                .tabItem { Label(L10n.Tab.setup, systemImage: "gearshape") }
                .tag(Tab.setup)
            LayoutSettingsView()
                .tabItem { Label(L10n.Layout.title, systemImage: "rectangle.split.2x1") }
                .tag(Tab.layout)
            RemoteTabView(goToSetup: { tab = .setup })
                .tabItem { Label(L10n.Tab.remote, systemImage: "keyboard") }
                .tag(Tab.remote)
            SettingsView()
                .tabItem { Label(L10n.Tab.settings, systemImage: "slider.horizontal.3") }
                .tag(Tab.settings)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 660, idealHeight: 800)
    }
}
