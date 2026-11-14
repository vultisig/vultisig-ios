//
//  SwapKeypadInput.swift
//  VultisigApp
//
//  The amount typed on the in-app keypad (the Withdraw keypad, `PerpsKeypad`).
//  The decimal separator is always ".", whatever the locale, and the number of
//  fraction digits is capped at the source coin's precision so the field can
//  never hold an amount the chain cannot represent.
//

import Foundation

enum SwapKeypadInput {
    /// Integer digits before the field stops taking more.
    static let maxIntegerDigits = 12

    static func apply(_ key: PerpsKeypadKey, to text: String, maxFractionDigits: Int) -> String {
        switch key {
        case .delete:
            let trimmed = String(text.dropLast())
            return trimmed == "0" ? "" : trimmed
        case .dot:
            guard maxFractionDigits > 0, !text.contains(".") else { return text }
            return text.isEmpty ? "0." : text + "."
        case .digit(let digit):
            guard (0...9).contains(digit) else { return text }
            if let dot = text.firstIndex(of: ".") {
                let fraction = text[text.index(after: dot)...]
                return fraction.count >= maxFractionDigits ? text : text + "\(digit)"
            }
            if text == "0" { return "\(digit)" }
            guard text.count < maxIntegerDigits else { return text }
            return text + "\(digit)"
        }
    }

    /// A Max or % amount from the existing logic, normalized for the keypad:
    /// "." decimals, no grouping, no trailing zeros, capped precision.
    static func normalized(_ amount: Decimal, maxFractionDigits: Int) -> String {
        guard amount > 0 else { return "" }
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, max(maxFractionDigits, 0), .down)
        // `Decimal`'s own description: exact at any precision (a
        // NumberFormatter goes through ~15 significant digits, which left dust
        // on 18-decimal tokens), always ".", no grouping, no exponent, no
        // trailing zeros.
        return rounded.description
    }

    /// "1234.5" as "1,234.5" for display, keeping a trailing "." or zeros the
    /// user is still typing. Grouping is "," and decimals "." in every locale.
    static func display(_ text: String) -> String {
        guard !text.isEmpty else { return "0" }
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integer = String(parts[0])
        var grouped = ""
        for (index, char) in integer.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(",") }
            grouped.append(char)
        }
        let integerText = String(grouped.reversed())
        guard parts.count > 1 else { return integerText.isEmpty ? "0" : integerText }
        return (integerText.isEmpty ? "0" : integerText) + "." + parts[1]
    }
}
