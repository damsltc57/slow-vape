import Foundation

enum L10n {
    static let language = Bundle.main.preferredLocalizations.first == "fr" ? "fr" : "en"
    static let locale = Locale(identifier: language)

    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    static func puffs(_ count: Int) -> String {
        let singular = count == 1 || (language == "fr" && count == 0)
        return format(singular ? "puffs.one" : "puffs.other", number(count))
    }

    static func remaining(_ count: Int) -> String {
        format(count == 1 ? "limits.remaining.one" : "limits.remaining.other", number(count))
    }
}
