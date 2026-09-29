import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: Keys.soundEnabled)
        }
    }

    @Published var selectedDurationMode: DurationMode {
        didSet {
            defaults.set(selectedDurationMode.rawValue, forKey: Keys.durationMode)
        }
    }

    @Published private var storedCustomDurationSeconds: Double

    var customDurationSeconds: Double {
        get { storedCustomDurationSeconds }
        set {
            let normalized = Self.clampDuration(newValue)
            if storedCustomDurationSeconds != normalized {
                storedCustomDurationSeconds = normalized
            }
            defaults.set(normalized, forKey: Keys.customDurationSeconds)
        }
    }

    @Published var languageMode: LanguageMode {
        didSet {
            defaults.set(languageMode.rawValue, forKey: Keys.languageMode)
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
        }
    }

    enum DurationMode: String, Identifiable {
        case thirtySeconds
        case sixtySeconds
        case twoMinutes
        case custom
        case infinite

        var id: String { rawValue }

        static var primaryCases: [DurationMode] {
            [.thirtySeconds, .sixtySeconds, .twoMinutes, .custom, .infinite]
        }

        var localizationKey: String {
            switch self {
            case .thirtySeconds:
                "duration.30"
            case .sixtySeconds:
                "duration.60"
            case .twoMinutes:
                "duration.120"
            case .custom:
                "duration.custom"
            case .infinite:
                "duration.manual"
            }
        }
    }

    enum LanguageMode: String, Identifiable {
        case automatic
        case spanish
        case english

        var id: String { rawValue }
    }

    enum AppearanceMode: String, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system:
                nil
            case .light:
                .light
            case .dark:
                .dark
            }
        }
    }

    private enum Keys {
        static let soundEnabled = "soundEnabled"
        static let durationMode = "durationMode"
        static let customDurationSeconds = "customDurationSeconds"
        static let languageMode = "languageMode"
        static let appearanceMode = "appearanceMode"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.soundEnabled) == nil {
            soundEnabled = true
        } else {
            soundEnabled = defaults.bool(forKey: Keys.soundEnabled)
        }

        if let storedMode = defaults.string(forKey: Keys.durationMode),
           let mode = DurationMode(rawValue: storedMode) {
            selectedDurationMode = mode
        } else {
            selectedDurationMode = .sixtySeconds
        }

        if let storedLanguage = defaults.string(forKey: Keys.languageMode),
           let language = LanguageMode(rawValue: storedLanguage) {
            languageMode = language
        } else {
            languageMode = .automatic
        }

        if let storedAppearance = defaults.string(forKey: Keys.appearanceMode),
           let appearance = AppearanceMode(rawValue: storedAppearance) {
            appearanceMode = appearance
        } else {
            appearanceMode = .system
        }

        let savedDuration = defaults.double(forKey: Keys.customDurationSeconds)
        if savedDuration > 0 {
            storedCustomDurationSeconds = Self.clampDuration(savedDuration)
        } else {
            storedCustomDurationSeconds = CleaningDuration.defaultSeconds
        }
    }

    var selectedDuration: CleaningDuration {
        switch selectedDurationMode {
        case .thirtySeconds:
            .timed(seconds: 30)
        case .sixtySeconds:
            .timed(seconds: CleaningDuration.defaultSeconds)
        case .twoMinutes:
            .timed(seconds: 120)
        case .custom:
            .timed(seconds: customDurationSeconds)
        case .infinite:
            .infinite
        }
    }

    nonisolated static func clampDuration(_ seconds: Double) -> Double {
        guard seconds.isFinite else {
            if seconds.isNaN {
                return CleaningDuration.defaultSeconds
            }
            return seconds.sign == .minus
                ? CleaningDuration.minimumSeconds
                : CleaningDuration.maximumTimedSeconds
        }

        return min(max(seconds, CleaningDuration.minimumSeconds), CleaningDuration.maximumTimedSeconds)
    }
}
