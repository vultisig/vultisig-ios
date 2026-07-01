//
//  CompactAmountText.swift
//  VultisigApp
//

import SwiftUI

/// Renders a fiat price, upgrading the compact subscript notation produced by
/// `Decimal.formatToFiatPrice()` (e.g. "$0.0₄1234") into a real, legibly sized subscript instead of
/// the small Unicode glyph. Prices without leading-zero collapsing render as plain text.
///
/// Apply `.foregroundStyle` on the view to colour every run; font styling is controlled through the
/// `fontStyle`/`size` parameters so the subscript can be scaled relative to the base size.
struct CompactAmountText: View {
    let amount: Decimal
    var includeCurrencySymbol: Bool = true
    var fontStyle: FontStyle = .satoshiMedium
    var size: CGFloat = 12

    private static let subscriptScale: CGFloat = 0.7
    private static let subscriptBaselineFraction: CGFloat = 0.12

    var body: some View {
        segments.reduce(Text(verbatim: "")) { text, segment in
            switch segment {
            case .plain(let value):
                return text + Text(verbatim: value).font(fontStyle.size(size))
            case .zeroCount(let value):
                return text + Text(verbatim: value)
                    .font(fontStyle.size(size * Self.subscriptScale))
                    .baselineOffset(-size * Self.subscriptBaselineFraction)
            }
        }
    }

    private var segments: [Segment] {
        Self.segments(for: amount.formatToFiatPrice(includeCurrencySymbol: includeCurrencySymbol))
    }

    // MARK: - Parsing

    enum Segment: Equatable {
        case plain(String)
        case zeroCount(String)
    }

    private static let digitForSubscript: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4",
        "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9"
    ]

    /// Splits a formatted price into plain runs and subscript-digit runs, converting the Unicode
    /// subscript glyphs back into normal digits so they can be rendered at a legible size.
    static func segments(for formatted: String) -> [Segment] {
        var segments: [Segment] = []
        var plain = ""
        var zeroCount = ""

        for character in formatted {
            if let digit = digitForSubscript[character] {
                if !plain.isEmpty {
                    segments.append(.plain(plain))
                    plain = ""
                }
                zeroCount.append(digit)
            } else {
                if !zeroCount.isEmpty {
                    segments.append(.zeroCount(zeroCount))
                    zeroCount = ""
                }
                plain.append(character)
            }
        }
        if !plain.isEmpty { segments.append(.plain(plain)) }
        if !zeroCount.isEmpty { segments.append(.zeroCount(zeroCount)) }
        return segments
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        CompactAmountText(amount: Decimal(string: "0.00000003")!)
        CompactAmountText(amount: Decimal(string: "0.00001234")!)
        CompactAmountText(amount: Decimal(string: "0.0001234")!)
        CompactAmountText(amount: Decimal(string: "0.00006")!)
        CompactAmountText(amount: Decimal(string: "1.23")!)
    }
    .foregroundStyle(Theme.colors.textPrimary)
    .padding()
}
