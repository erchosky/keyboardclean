import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .frame(width: 600, height: 540)
                .tabItem {
                    Label("settings.tab.general", systemImage: "gearshape")
                }

            AutomationSettingsView()
                .frame(width: 600, height: 540)
                .tabItem {
                    Label("settings.tab.automation", systemImage: "bolt")
                }

            ActivitySettingsView()
                .frame(width: 600, height: 540)
                .tabItem {
                    Label("settings.tab.activity", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}
