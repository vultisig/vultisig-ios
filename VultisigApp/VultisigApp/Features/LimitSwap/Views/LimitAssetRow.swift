//
//  LimitAssetRow.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Single asset row (chain header + coin pill + amount field)

enum LimitAssetRowKind {
    case sell
    case buy

    var labelKey: String {
        self == .sell ? "limitSwap.sell" : "limitSwap.buy"
    }
}

struct LimitAssetRow: View {

    let kind: LimitAssetRowKind
    let coin: Coin
    let asset: LimitSwapAsset
    @Binding var amountText: String
    /// Non-nil when the amount is user-editable, and names the field's focus
    /// identity — the two are inseparable, since an editable field is exactly
    /// what the parent's keyboard accessory has to distinguish. `nil` renders the
    /// amount as read-only text (the computed Buy side).
    let editableFocus: LimitFocusField?
    /// Owned by `LimitSwapBodyView`, which renders the single keyboard accessory.
    var focusedField: FocusState<LimitFocusField?>.Binding
    let computedAmount: Decimal?
    let usdPricePerUnit: Decimal
    let onPickAsset: () -> Void

    var body: some View {
        // Both the chain chip and the coin pill open the same asset picker in the
        // Limit form, so `onTapChain` and `onTapCoin` share `onPickAsset`. Balance
        // is shown only on the Sell row (the Buy amount is computed). The editable
        // Sell field participates in the form's single keyboard toolbar via `focus`.
        SwapAssetCard<LimitFocusField>(
            label: kind.labelKey.localized,
            chainLogo: asset.chainLogo,
            chainName: asset.chain.name,
            onTapChain: onPickAsset,
            coinLogo: asset.logo,
            // No chain badge on a native asset (its icon already is the chain) —
            // matches the Market card, which passes a nil `coin.tokenChainLogo`.
            coinChainLogo: asset.isNativeToken ? nil : asset.chainLogo,
            ticker: asset.ticker,
            onTapCoin: onPickAsset,
            balance: kind == .sell ? "\(coin.balanceString) \(coin.ticker)" : nil,
            amount: $amountText,
            isEditable: editableFocus != nil,
            focus: focusedField,
            focusValue: editableFocus,
            fiat: fiatLine,
            isSecondRow: kind == .buy
        )
    }

    private var fiatLine: String {
        let amount = effectiveAmount
        guard usdPricePerUnit > 0, amount > 0 else { return "$0.00" }
        let usd = amount * usdPricePerUnit
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        let value = formatter.string(from: NSDecimalNumber(decimal: usd)) ?? "0.00"
        return "$\(value)"
    }

    private var effectiveAmount: Decimal {
        if let computedAmount {
            return computedAmount
        }
        // Locale-aware so the fiat sub-line doesn't mis-read a pasted grouped
        // number (shares the parser the amount field itself uses).
        return parseLimitDecimal(amountText)
    }
}
