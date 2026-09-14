//
//  SwapFromToField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

/// Market-swap adapter over the shared `SwapAssetCard`. Maps the Market
/// `SwapDetailsViewModel` / `Coin` / `Chain` state onto the presentational card
/// and keeps input-unit selection and quote side effects out of the shared card.
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

    @AppStorage("currency") private var currencyCode = SettingsCurrency.USD.rawValue

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
            amount: inputBinding,
            isEditable: isFromField,
            amountPrefix: isFromField && detailsViewModel.isFromInputFiat ? currencySymbol : nil,
            amountAccessibilityLabel: isFromField ? "\(title.localized), \(inputUnit)" : nil,
            onEditingChanged: editingChanged,
            fiat: equivalent,
            onTapEquivalent: equivalentAction,
            equivalentAccessibilityLabel: String(format: "swapEnterAmountIn".localized, alternateUnit),
            isSecondRow: !isFromField
        )
        // Crossfade the To amount + its fiat as the quote lands (the To value is
        // never skeletoned — it always carries the `~` estimate then the firm
        // amount). Matches the pre-adapter behavior. The From field is excluded so
        // typing isn't animated.
        .animation(isFromField ? nil : .easeInOut(duration: 0.25), value: amount)
        .animation(isFromField ? nil : .easeInOut(duration: 0.25), value: fiatAmount)
        .onAppear { refreshCurrencyContext() }
        .onChange(of: currencyCode) { _, _ in refreshCurrencyContext() }
        .onDisappear {
            if isFromField { detailsViewModel.setFromInputEditing(false) }
        }
    }

    private var editingChanged: ((Bool) -> Void)? {
        guard isFromField else { return nil }
        return { detailsViewModel.setFromInputEditing($0) }
    }

    private var equivalentAction: (() -> Void)? {
        guard canToggle else { return nil }
        return { detailsViewModel.toggleFromInputMode() }
    }

    private var inputBinding: Binding<String> {
        guard isFromField else { return $amount }
        return Binding(
            get: { detailsViewModel.fromInputText },
            set: { text in
                detailsViewModel.editFromInput(text, vault: vault)
                detailsViewModel.showAllPercentageButtons = true
            }
        )
    }

    private var canToggle: Bool { isFromField && detailsViewModel.canToggleFromInputMode }
    private var inputUnit: String { detailsViewModel.isFromInputFiat ? detailsViewModel.fromInputCurrencyCode : coin.ticker }
    private var alternateUnit: String { detailsViewModel.isFromInputFiat ? coin.ticker : detailsViewModel.fromInputCurrencyCode }

    private var equivalent: String {
        if isFromField && detailsViewModel.isFromInputFiat {
            return "\(amount.isEmpty ? "0" : amount) \(coin.ticker)"
        }
        return isFromField ? fiatAmount : fiatAmount.formatToFiat(includeCurrencySymbol: true)
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        formatter.currencyCode = detailsViewModel.fromInputCurrencyCode
        return formatter.currencySymbol ?? detailsViewModel.fromInputCurrencyCode
    }

    private func refreshCurrencyContext() {
        guard isFromField else { return }
        detailsViewModel.refreshFromInputContext(currency: SettingsCurrency(rawValue: currencyCode) ?? .USD)
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
