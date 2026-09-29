import SwiftUI

@main
struct KyboardcleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("menuBarEnabled") private var menuBarEnabled = false

    @StateObject private var permissions = PermissionsManager.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var session = CleaningSessionManager.shared
    @StateObject private var history = CleaningHistoryStore.shared
    @StateObject private var shortcutManager = GlobalShortcutManager.shared
    @StateObject private var reminderManager = ReminderManager.shared

    var body: some Scene {
        Window("Kyboardclean", id: "main") {
            MainView()
                .environmentObject(permissions)
                .environmentObject(settings)
                .environmentObject(session)
                .environment(\.locale, AppText.locale(for: settings.languageMode))
                .preferredColorScheme(settings.appearanceMode.colorScheme)
                .frame(minWidth: 460, idealWidth: 520, minHeight: 500, idealHeight: 610)
                .onAppear {
                    session.refreshPreflightStatus()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 610)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button(AppText.string("menu.about", language: settings.languageMode)) {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Kyboardclean",
                            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
                        ]
                    )
                }
            }
            CommandMenu(AppText.string("menu.help", language: settings.languageMode)) {
                Button(AppText.string("menu.help.readme", language: settings.languageMode)) {
                    let effectiveLanguage = AppText.effectiveLanguage(for: settings.languageMode)
                    let resourceName = effectiveLanguage == .english ? "README_en" : "README"
                    if let url = Bundle.main.url(forResource: resourceName, withExtension: "md") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(permissions)
                .environmentObject(settings)
                .environmentObject(session)
                .environmentObject(history)
                .environmentObject(shortcutManager)
                .environmentObject(reminderManager)
                .environment(\.locale, AppText.locale(for: settings.languageMode))
                .preferredColorScheme(settings.appearanceMode.colorScheme)
        }

        MenuBarExtra(
            "Kyboardclean",
            systemImage: "keyboard",
            isInserted: $menuBarEnabled
        ) {
            MenuBarView()
                .environmentObject(permissions)
                .environmentObject(settings)
                .environmentObject(session)
        }
        .menuBarExtraStyle(.menu)
    }
}
