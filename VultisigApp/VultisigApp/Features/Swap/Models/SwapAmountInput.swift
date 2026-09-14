import Foundation

/// Fiat is an editable presentation of the canonical token amount, never its storage.
struct SwapAmountInput {
    struct Context: Equatable {
        let sourceID: String
        let currency: String
        let decimals: Int
        let rate: Decimal

        init?(sourceID: String, currency: String, decimals: Int, rate: Double?) {
            guard let rate, rate.isFinite, rate > 0, (0...38).contains(decimals),
                  let decimal = Decimal(string: String(rate), locale: Locale(identifier: "en_US_POSIX")),
                  !decimal.isNaN, decimal > 0 else { return nil }
            self.sourceID = sourceID
            self.currency = currency
            self.decimals = decimals
            self.rate = decimal
        }

        func matchesIdentity(_ other: Context) -> Bool {
            sourceID == other.sourceID && currency == other.currency && decimals == other.decimals
        }
    }

    private(set) var isFiat = false
    private(set) var draft = ""
    private(set) var context: Context?
    private(set) var isEditing = false
    private var latestContext: Context?

    mutating func refresh(context newContext: Context?, tokenAmount: Decimal, locale: Locale = .current) {
        guard let newContext else { reset(); return }
        if let context, !context.matchesIdentity(newContext) { reset() }
        latestContext = newContext
        // A focused fiat field and its equivalent share one captured price. A
        // background tick must never revalue the amount the user will sign.
        guard !(isFiat && isEditing) else { return }
        context = newContext
        synchronize(tokenAmount: tokenAmount, locale: locale)
    }

    mutating func setEditing(_ editing: Bool, tokenAmount: Decimal, locale: Locale = .current) {
        isEditing = editing
        if !editing { refresh(context: latestContext, tokenAmount: tokenAmount, locale: locale) }
    }

    mutating func toggle(tokenAmount: Decimal, locale: Locale = .current) {
        if isFiat {
            isFiat = false
            context = latestContext
        } else if context != nil {
            isFiat = true
        }
        synchronize(tokenAmount: tokenAmount, locale: locale)
    }

    mutating func synchronize(tokenAmount: Decimal, locale: Locale = .current) {
        guard let context else { draft = ""; return }
        var amount = tokenAmount
        var price = context.rate
        var fiat = Decimal.zero
        let result = NSDecimalMultiply(&fiat, &amount, &price, .down)
        guard result == .noError || result == .lossOfPrecision, !fiat.isNaN else { reset(); return }
        draft = Self.fiatText(fiat, currency: context.currency, locale: locale)
    }

    /// Invalid input clears the token side so no previous quote remains actionable.
    /// The draft stays visible, allowing correction of intermediate/invalid edits.
    mutating func editFiat(_ text: String, locale: Locale = .current) -> String {
        guard isFiat else { return "" }
        draft = text
        guard let context, let fiat = Self.parse(text, locale: locale) else { return "" }
        var numerator = fiat
        var rate = context.rate
        var tokens = Decimal.zero
        let result = NSDecimalDivide(&tokens, &numerator, &rate, .down)
        if result == .underflow { return "0" }
        guard result == .noError || result == .lossOfPrecision, !tokens.isNaN else { return "" }
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &tokens, context.decimals, .down)
        return Self.text(rounded, locale: locale)
    }

    mutating func reset() {
        isFiat = false
        draft = ""
        context = nil
        latestContext = nil
    }

    /// Token entry historically accepts a POSIX paste after trying the current
    /// locale. Keep that ordering (so de_DE 1.500 remains grouped 1500), while
    /// validating the whole string and retaining Decimal precision in both paths.
    static func parseToken(_ text: String, locale: Locale = .current) -> Decimal? {
        parse(text, locale: locale) ?? parse(text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Strict whole-input parsing avoids NumberFormatter's partial matches and
    /// Double intermediates. Accept localized decimal digits and valid grouping.
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        guard text.count <= 80 else { return nil }
        let decimal = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        let parts = text.components(separatedBy: decimal)
        guard parts.count <= 2 else { return nil }
        let groups = parts[0].components(separatedBy: grouping)
        if groups.count > 1 {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            let primary = formatter.groupingSize
            let secondary = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary
            guard primary > 0, groups[0].first?.wholeNumberValue != 0, groups.last?.count == primary,
                  (1...secondary).contains(groups[0].count),
                  groups.dropFirst().dropLast().allSatisfy({ $0.count == secondary }) else { return nil }
        }
        let integer = groups.joined()
        let fraction = parts.count == 2 ? parts[1] : ""
        let digits = integer + fraction
        func latinDigits(_ value: String) -> String? {
            var result = ""
            for character in value {
                guard character.unicodeScalars.count == 1,
                      character.unicodeScalars.first?.properties.numericType == .decimal,
                      let digit = character.wholeNumberValue else { return nil }
                result += String(digit)
            }
            return result
        }
        guard let whole = latinDigits(integer), let fractional = latinDigits(fraction) else { return nil }
        guard (whole + fractional).drop(while: { $0 == "0" }).count <= 38 else { return nil }
        if digits.isEmpty { return text.isEmpty || text == decimal ? .zero : nil }
        return Decimal(string: (whole.isEmpty ? "0" : whole) + "." + fractional,
                       locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func fiatText(_ amount: Decimal, currency: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        var scale = formatter.maximumFractionDigits
        // Preserve meaningful sub-unit amounts while avoiding arithmetic tails
        // such as 9.999999999999999999 after token quantization. Display-only:
        // the rounded draft never becomes canonical unless the user edits it.
        if amount > 0 && amount < Decimal(sign: .plus, exponent: -scale, significand: 1) {
            var scaled = amount
            var leadingPlaces = 0
            while scaled < 1 && leadingPlaces < 127 {
                scaled *= 10
                leadingPlaces += 1
            }
            scale = min(127, leadingPlaces + 2)
        }
        var original = amount
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &original, scale, .plain)
        return text(rounded, locale: locale)
    }

    static func text(_ amount: Decimal, locale: Locale = .current) -> String {
        NSDecimalNumber(decimal: amount).stringValue.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }
}
