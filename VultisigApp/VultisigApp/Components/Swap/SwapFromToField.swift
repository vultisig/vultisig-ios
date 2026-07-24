//
//  SwapFromToField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

/// Market-swap adapter over the shared `SwapAssetCard`. Maps the Market
/// `SwapDetailsViewModel` / `Coin` / `Chain` state onto the presentational card
/// and keeps the Market-only keystroke side-effects (immediate-vs-debounced quote
/// fetch) here, out of the shared card. The public init is unchanged so
/// `SwapDetailsScreen` keeps working as-is.
struct SwapFromToField: View {
    let title: String
    let vault: Vault
    let coin: Coin
    let fiatAmount: String
    @Binding var amount: String
    @Binding var selectedChain: Chain?
    @Binding var showNetworkSelectSheet: Bool
    @Binding var showCoinSelectSheet: Bool
    @Bindable var detailsViewModel: SwapDetailsViewModel
    let handlePercentageSelection: ((Int) -> Void)?

    @StateObject var referredViewModel = ReferredViewModel()

    private var isFromField: Bool { title == "from" }

    var body: some View {
        SwapAssetCard<Never>(
            label: NSLocalizedString(title, comment: ""),
            chainLogo: selectedChain?.logo ?? "",
            chainName: selectedChain?.name ?? "",
            onTapChain: { showNetworkSelectSheet = true },
            coinLogo: coin.logo,
            coinChainLogo: coin.tokenChainLogo,
            ticker: coin.ticker,
            onTapCoin: { showCoinSelectSheet = true },
            // Market shows the balance on both the From and To rows.
            balance: "\(coin.balanceString) \(coin.ticker)",
            amount: $amount,
            isEditable: isFromField,
            // Runs on USER edits only (not the programmatic percentage-button set,
            // which would otherwise double-fetch and clear the selected pill).
            onEdit: isFromField ? handleAmountEdit : nil,
            fiat: fiatAmount.formatToFiat(includeCurrencySymbol: true),
            isSecondRow: !isFromField
        )
        // Crossfade the To amount + its fiat as the quote lands (the To value is
        // never skeletoned — it always carries the `~` estimate then the firm
        // amount). Matches the pre-adapter behavior.
        .animation(.easeInOut(duration: 0.25), value: amount)
        .animation(.easeInOut(duration: 0.25), value: fiatAmount)
        .onLoad {
            referredViewModel.setData()
        }
    }

    private func handleAmountEdit(oldValue: String, newValue: String) {
        // A multi-character jump (paste, autofill, or clearing the field to a
        // value) is a discrete action — fetch immediately instead of waiting out
        // the keystroke debounce. Single-char edits stay debounced.
        let immediate = abs(newValue.count - oldValue.count) > 1
        detailsViewModel.updateFromAmount(
            vault: vault,
            referredCode: referredViewModel.savedReferredCode,
            immediate: immediate
        )
        detailsViewModel.showAllPercentageButtons = true
    }
}

#Preview {
    SwapFromToField(
        title: "from",
        vault: Vault.example,
        coin: Coin.example,
        fiatAmount: "0",
        amount: .constant("0"),
        selectedChain: .constant(Chain.example),
        showNetworkSelectSheet: .constant(false),
        showCoinSelectSheet: .constant(false),
        detailsViewModel: SwapDetailsViewModel(),
        handlePercentageSelection: { _ in }
    )
}
