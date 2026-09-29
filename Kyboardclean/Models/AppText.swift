import Foundation

enum AppText {
    static func string(_ key: String, language: AppSettings.LanguageMode) -> String {
        localizedString(key, language: language)
    }

    static func string(_ key: String, language: AppSettings.LanguageMode, _ arguments: CVarArg...) -> String {
        let format = localizedString(key, language: language)
        return String(format: format, locale: locale(for: language), arguments: arguments)
    }

    static func duration(_ duration: CleaningDuration, language: AppSettings.LanguageMode) -> String {
        switch duration {
        case .timed(let seconds):
            let value = Int(seconds.rounded())
            if value < 60 {
                return string("duration.seconds.short", language: language, value)
            }

            let minutes = value / 60
            let remaining = value % 60
            if remaining == 0 {
                return string("duration.minutes.short", language: language, minutes)
            }

            return string("duration.minutes.seconds.short", language: language, minutes, remaining)
        case .infinite:
            return string("duration.manualWithLimit", language: language)
        }
    }

    static func stopReason(_ reason: StopReason, language: AppSettings.LanguageMode) -> String {
        string(reason.localizationKey, language: language)
    }

    static func sessionError(_ error: SessionErrorCode, language: AppSettings.LanguageMode) -> String {
        string(error.localizationKey, language: language)
    }

    static func effectiveLanguage(
        for language: AppSettings.LanguageMode,
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations
    ) -> AppSettings.LanguageMode {
        guard language == .automatic else {
            return language
        }

        for localization in preferredLocalizations {
            let languageCode = Locale(identifier: localization).language.languageCode?.identifier
            if languageCode == "es" {
                return .spanish
            }
            if languageCode == "en" {
                return .english
            }
        }

        return .english
    }

    static func locale(for language: AppSettings.LanguageMode) -> Locale {
        switch effectiveLanguage(for: language) {
        case .automatic, .english:
            englishLocale
        case .spanish:
            spanishLocale
        }
    }

    private static func localizedString(_ key: String, language: AppSettings.LanguageMode) -> String {
        let bundle = bundle(for: language)
        let localized = NSLocalizedString(key, tableName: nil, bundle: bundle, value: "", comment: "")
        if !localized.isEmpty {
            return localized
        }

        let english = NSLocalizedString(key, tableName: nil, bundle: englishBundle, value: "", comment: "")
        return english.isEmpty ? key : english
    }

    private static func bundle(for language: AppSettings.LanguageMode) -> Bundle {
        switch effectiveLanguage(for: language) {
        case .automatic, .english:
            englishBundle
        case .spanish:
            spanishBundle
        }
    }

    private static let spanishBundle = localizedBundle(code: "es")
    private static let englishBundle = localizedBundle(code: "en")
    private static let spanishLocale = Locale(identifier: "es")
    private static let englishLocale = Locale(identifier: "en")

    private static func localizedBundle(code: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }

        return bundle
    }

}

extension StopReason {
    var localizationKey: String {
        switch self {
        case .manual:
            "stop.manual"
        case .timerFinished:
            "stop.timerFinished"
        case .emergencyShortcut:
            "stop.emergencyShortcut"
        case .escapeSequence:
            "stop.escapeSequence"
        case .hardSafetyLimit:
            "stop.hardSafetyLimit"
        case .eventTapFailed:
            "stop.eventTapFailed"
        case .unsafeState:
            "stop.unsafeState"
        case .permissionLost:
            "stop.permissionLost"
        case .secureEventInput:
            "stop.secureEventInput"
        case .overlayUnavailable:
            "stop.overlayUnavailable"
        case .appTerminated:
            "stop.appTerminated"
        case .systemEvent:
            "stop.systemEvent"
        }
    }
}
