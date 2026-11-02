//
//  FiatFormatLocale.swift
//  VultisigApp
//

import Foundation

/// The locale fiat amounts are formatted in. It follows the selected currency only, never the app
/// language, so a balance reads the same in every language and on every Vultisig app.
enum FiatFormatLocale {
    static func locale(for currencyCode: String) -> Locale {
        locales[currencyCode.uppercased()] ?? defaultLocale
    }

    /// A currency-style formatter in the currency's locale. CAD, AUD, SGD and CNY show `CA$`, `A$`,
    /// `S$` and `CN¥`, so none reads as US dollars or yen.
    static func currencyFormatter(for currencyCode: String) -> NumberFormatter {
        let code = currencyCode.uppercased()
        let formatter = NumberFormatter()
        formatter.locale = locale(for: code)
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        if let symbol = disambiguatedSymbols[code] {
            formatter.currencySymbol = symbol
        }
        return formatter
    }

    private static let defaultLocale = Locale(identifier: "en_US")

    private static let locales: [String: Locale] = [
        "USD": "en_US",
        "EUR": "de_DE",
        "GBP": "en_GB",
        "CHF": "de_CH",
        "JPY": "ja_JP",
        "CNY": "zh_CN",
        "CAD": "en_CA",
        "AUD": "en_AU",
        "SGD": "en_SG",
        "SEK": "sv_SE"
    ].mapValues(Locale.init(identifier:))

    private static let disambiguatedSymbols: [String: String] = [
        "CAD": "CA$",
        "AUD": "A$",
        "SGD": "S$",
        "CNY": "CN¥"
    ]
}
