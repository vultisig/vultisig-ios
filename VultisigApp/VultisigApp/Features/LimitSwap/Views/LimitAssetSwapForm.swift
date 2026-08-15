//
//  LimitAssetSwapForm.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Asset swap form (Sell + middle swap button + Buy)
//
// A flat card in the Uniswap layout — always visible alongside the price, so the
// amount the target price applies to is never hidden.

struct LimitAssetSwapForm: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin
    @Binding var sourceAmountText: String
    @Binding var buyAmountText: String
    /// Owned by `LimitSwapBodyView`, which renders the single keyboard accessory.
    var focusedField: FocusState<LimitFocusField?>.Binding
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void

    var body: some View {
        ZStack {
            // Shared with the notch-center inset so the toggle seats in a full circle.
            VStack(spacing: swapCardSpacing) {
                LimitAssetRow(
                    kind: .sell,
                    coin: fromCoin,
                    asset: vm.draft.fromAsset,
                    amountText: $sourceAmountText,
                    editableFocus: .sellAmount,
                    focusedField: focusedField,
                    computedAmount: nil,
                    usdPricePerUnit: Decimal(fromCoin.price),
                    onPickAsset: onPickFromAsset
                )
                .id(LimitScrollAnchor.sell)

                LimitAssetRow(
                    kind: .buy,
                    coin: toCoin,
                    asset: vm.draft.toAsset,
                    amountText: $buyAmountText,
                    editableFocus: .buyAmount,
                    focusedField: focusedField,
                    // The fiat sub-line reads the DERIVED output, not the typed
                    // text, so it states what the order actually guarantees even
                    // while the field still shows what was asked for.
                    computedAmount: buyAmountDecimal,
                    usdPricePerUnit: vm.targetUsdPricePerUnit,
                    onPickAsset: onPickToAsset
                )
                .id(LimitScrollAnchor.buy)
            }

            // Shared with the market swap form: same visual + spring flip.
            SwapAssetsButton {
                onSwapAssets()
            }
        }
    }

    /// Buy amount as the ORDER guarantees it — the VM derives it from the signed
    /// `computeLim` path so it can't diverge from the memo's truncated LIM. `nil`
    /// when not yet computable (row shows "0").
    private var buyAmountDecimal: Decimal? {
        let amount = vm.expectedBuyAmount
        return amount > 0 ? amount : nil
    }

}
