import SwiftUI

struct ContentView: View {
    @State private var tab = Tab.setup

    private enum Tab {
        case setup, layout, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            SetupView()
                .tabItem { Label(L10n.Tab.setup, systemImage: "gearshape") }
                .tag(Tab.setup)
            LayoutSettingsView()
                .tabItem { Label(L10n.Layout.title, systemImage: "rectangle.split.2x1") }
                .tag(Tab.layout)
            SettingsView()
                .tabItem { Label(L10n.Tab.settings, systemImage: "slider.horizontal.3") }
                .tag(Tab.settings)
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 640, minHeight: 480, idealHeight: 600)
    }
}
