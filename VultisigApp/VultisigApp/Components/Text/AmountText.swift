//
//  AmountText.swift
//  VultisigApp
//

import SwiftUI

/// Renders a pre-formatted crypto/fiat amount string (balance, value, fee, price, …).
///
/// Formatting stays at the call site (e.g. `Decimal.formatToFiatPrice()`), so swapping a plain
/// `Text` for `AmountText` is a display-only change — the underlying value is never recomputed here.
/// Font, colour and size come from the caller via standard SwiftUI modifiers (`.font(…)`,
/// `.foregroundStyle(…)`), which cascade onto the inner `Text`. Compact subscript notation for tiny
/// prices (e.g. `$0.0₇3`) arrives as the formatter's Unicode subscript glyphs and renders as-is.
struct AmountText: View {
    private let amount: String

    init(_ amount: String) {
        self.amount = amount
    }

    var body: some View {
        Text(verbatim: amount)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        AmountText(Decimal(string: "0.00000003")!.formatToFiatPrice())
        AmountText(Decimal(string: "0.00001234")!.formatToFiatPrice())
        AmountText(Decimal(string: "1.23")!.formatToFiatPrice())
    }
    .font(Theme.fonts.priceBodyS)
    .foregroundStyle(Theme.colors.textPrimary)
    .padding()
}
