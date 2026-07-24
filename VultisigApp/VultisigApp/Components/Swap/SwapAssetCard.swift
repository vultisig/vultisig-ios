//
//  SwapAssetCard.swift
//  VultisigApp
//

import SwiftUI

/// The shared Sell/Buy (a.k.a. From/To) asset card used by BOTH swap forms — the
/// Market form (`SwapFromToField`) and the Limit form (`LimitAssetRow`). Purely
/// presentational (no view model): each form is a thin adapter that maps its own
/// state onto these inputs, so the two cards can no longer visually diverge.
///
/// The only intended differences between the two forms are the row `label`
/// (From/To vs Sell/Buy) and whether a `balance` is supplied (Market shows it on
/// both rows; Limit only on the Sell row).
///
/// `Focus` is the focus-identity type of the form's keyboard accessory. The Market
/// form has no such accessory, so it uses `SwapAssetCard<Never>` and passes no
/// focus; the Limit form passes its `@FocusState` binding so the shared editable
/// field participates in its single keyboard toolbar.
struct SwapAssetCard<Focus: Hashable>: View {
    let label: String

    let chainLogo: String
    let chainName: String
    let onTapChain: () -> Void

    let coinLogo: String
    /// Chain badge overlaid on the coin icon. `nil` (a native coin) shows no badge;
    /// pass the value through as-is rather than coercing to `""`, which would render
    /// an empty badge.
    let coinChainLogo: String?
    let ticker: String
    let onTapCoin: () -> Void

    /// Balance line at the trailing edge of the header. `nil` hides it (the Limit
    /// Buy row); Market supplies it on both rows.
    let balance: String?

    @Binding var amount: String
    let isEditable: Bool
    var placeholder: String = "0"
    /// Fires ONLY on a user edit of the editable field (typed/pasted), with the
    /// old and new text — never on a programmatic `amount` change. The adapter puts
    /// its form-specific side effects here so a programmatic set (e.g. a percentage
    /// button) doesn't re-trigger them.
    var onEdit: ((_ old: String, _ new: String) -> Void)?

    /// Optional keyboard-accessory focus wiring (Limit only). Both must be set for
    /// the editable field to bind to the form's `@FocusState`.
    var focus: FocusState<Focus?>.Binding?
    var focusValue: Focus?

    /// Always-shown fiat sub-line under the amount.
    let fiat: String

    /// The Buy/To card is the same shape rotated 180° so its notch sits on the top
    /// edge; both cards' notches then meet as one circle around the shared toggle.
    let isSecondRow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(16)
        // Fixed card height (Figma cards are 333×112; 116 is the smallest that fits
        // the Satoshi-22 amount + 36pt coin pill + 16 padding/spacing without
        // clipping — Sell needs 115, Buy 113). Constant regardless of content, with
        // the content pinned top-leading (header row on top) like the Figma.
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
        .background(
            NotchedRectangle(notchCenterInset: swapCardSpacing / 2)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
                .rotationEffect(.degrees(isSecondRow ? 180 : 0))
        )
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text(label)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                chainSelector
            }
            Spacer(minLength: 8)
            if let balance {
                Text(balance)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var chainSelector: some View {
        Button(action: onTapChain) {
            HStack(spacing: 4) {
                if !chainLogo.isEmpty {
                    AsyncImageView(
                        logo: chainLogo,
                        size: CGSize(width: 16, height: 16),
                        ticker: chainName,
                        tokenChainLogo: nil
                    )
                }
                Text(chainName)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .bold()
            }
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        HStack(alignment: .center) {
            coinPill
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                amountView
                    .font(Theme.fonts.priceTitle2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.trailing)
                Text(fiat)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var coinPill: some View {
        Button(action: onTapCoin) {
            HStack(spacing: 8) {
                if !coinLogo.isEmpty {
                    AsyncImageView(
                        logo: coinLogo,
                        size: CGSize(width: 36, height: 36),
                        ticker: ticker,
                        tokenChainLogo: coinChainLogo
                    )
                }
                Text(ticker)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                Image(systemName: "chevron.right")
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .bold()
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Theme.colors.bgSurface2)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var amountView: some View {
        if isEditable {
            editableAmount
        } else {
            // Read-only side (the computed Buy / quoted To amount): scalable so a
            // long number shrinks to fit instead of truncating.
            Text(amount)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private var editableAmount: some View {
        // Decimal-only: reject any non-numeric edit (typed or pasted). The iOS
        // decimal pad enforces this for free; macOS has no keypad.
        let decimal = Binding<String>(
            get: { amount },
            set: { newValue in
                guard newValue.isDecimalInput() else { return }
                let old = amount
                amount = newValue
                onEdit?(old, newValue)
            }
        )
        let field = TextField(placeholder, text: decimal)
            .textFieldStyle(.plain)
            .maxLength($amount)
            .disableAutocorrection(true)
            .lineLimit(1)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.decimalPad)
            .textContentType(.oneTimeCode)
            #endif
        if let focus, let focusValue {
            field.focused(focus, equals: focusValue)
        } else {
            field
        }
    }
}

#Preview {
    ZStack {
        Theme.colors.bgPrimary
        ZStack {
            VStack(spacing: swapCardSpacing) {
                SwapAssetCard<Never>(
                    label: "From",
                    chainLogo: "",
                    chainName: "Ethereum",
                    onTapChain: {},
                    coinLogo: "",
                    coinChainLogo: nil,
                    ticker: "USDT",
                    onTapCoin: {},
                    balance: "12,200.52 USDT",
                    amount: .constant("5200"),
                    isEditable: true,
                    fiat: "$5,200.55",
                    isSecondRow: false
                )
                SwapAssetCard<Never>(
                    label: "To",
                    chainLogo: "",
                    chainName: "Bitcoin",
                    onTapChain: {},
                    coinLogo: "",
                    coinChainLogo: nil,
                    ticker: "BTC",
                    onTapCoin: {},
                    balance: nil,
                    amount: .constant("0.0790275"),
                    isEditable: false,
                    fiat: "$5,200.55",
                    isSecondRow: true
                )
            }
            SwapAssetsButton {}
        }
        .padding(16)
    }
}
