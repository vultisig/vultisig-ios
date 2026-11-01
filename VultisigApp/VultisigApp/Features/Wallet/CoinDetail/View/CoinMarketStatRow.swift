//
//  CoinMarketStatRow.swift
//  VultisigApp
//
//  The label/value row the coin-detail market sections are built from, plus the
//  number formatting they share.
//

import SwiftUI

struct CoinMarketStatRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// Default trailing content: the value, in the price font.
struct CoinMarketStatValue: View {
    let value: String

    var body: some View {
        Text(value)
            .font(Theme.fonts.priceBodyS)
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.trailing)
    }
}

extension CoinMarketStatRow where Trailing == CoinMarketStatValue {
    init(title: String, value: String) {
        self.title = title
        self.trailing = { CoinMarketStatValue(value: value) }
    }
}

/// Number formatting for the market sections.
///
/// Every entry point returns `nil` for a missing or non-finite value so the
/// sections can simply drop the row: CoinGecko nulls anything it cannot compute
/// and a row reading "—" carries no information.
enum MarketStatFormatter {

    /// Fiat amount, abbreviated above a million.
    ///
    /// A market cap written out in full is a fourteen-digit number that nobody
    /// reads; `$1.28T` is the number people actually compare. The compact number
    /// and the symbol's side follow the currency's locale (`285,45 Mrd. €` for
    /// EUR), matching the iOS 18 compact currency style, which iOS 17 lacks.
    static func fiat(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }

        let decimal = Decimal(value)
        guard abs(decimal) >= 1_000_000 else {
            return decimal.formatToFiatPrice()
        }
        let currency = SettingsCurrency.current
        let formatter = FiatFormatLocale.currencyFormatter(for: currency.rawValue)
        let number = abs(decimal).formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...2))
                .rounded(rule: .down)
                .locale(currency.formattingLocale)
        )
        let isNegative = decimal < 0
        let prefix = (isNegative ? formatter.negativePrefix : formatter.positivePrefix) ?? ""
        let suffix = (isNegative ? formatter.negativeSuffix : formatter.positiveSuffix) ?? ""
        return "\(prefix)\(number)\(suffix)"
    }

    /// Exact fiat price, keeping the leading significant digits of a sub-cent
    /// token rather than collapsing it to `$0.00`.
    static func price(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return Decimal(value).formatToFiatPrice()
    }

    /// Token quantity with its ticker, e.g. `19.8M BTC`.
    static func supply(_ value: Double?, ticker: String) -> String? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return "\(Decimal(value).formatForDisplay()) \(ticker)"
    }

    /// Signed percentage from a *percentage* input (`-49.3` → `-49.30%`).
    static func percentage(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return signed(Decimal(value))
    }

    /// Signed percentage from a *fraction* input (`0.0421` → `+4.21%`).
    static func percentage(fraction: Double?) -> String? {
        guard let fraction, fraction.isFinite else { return nil }
        return signed(Decimal(fraction * 100))
    }

    static func date(_ value: Date?) -> String? {
        guard let value else { return nil }
        return value.formatted(date: .abbreviated, time: .omitted)
    }

    private static func signed(_ percentage: Decimal) -> String {
        let sign = percentage < 0 ? "" : "+"
        return "\(sign)\(percentage.formatToDecimal(digits: 2))%"
    }
}
