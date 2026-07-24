//
//  SwapFromToField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

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

    var body: some View {
        VStack(spacing: 16) {
            header
            content
        }
        .padding(16)
        .background(notchedBorder)
        .onLoad {
            referredViewModel.setData()
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            fromToLabel
            fromToChain
            Spacer()
            balance
        }
    }

    var content: some View {
        HStack {
            fromToCoin
            Spacer()
            VStack(spacing: 6) {
                fromToAmountField
                fiatBalance
            }
        }
    }

    var fromToLabel: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    var balance: some View {
        Text("\(coin.balanceString) \(coin.ticker)")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    /// Transparent card matching the Limit form: no fill, just a `borderLight`
    /// bordered `NotchedRectangle` (24 outer / 12 inner corners, concave cutout on
    /// the bottom edge). The "to" card is the same shape rotated 180° (corners flip
    /// 24/12 → 12/24, notch moves to the top edge). The notch center is inset half
    /// the inter-card gap so both cards' notches meet as one full circle around the
    /// shared toggle.
    var notchedBorder: some View {
        NotchedRectangle(notchCenterInset: swapCardSpacing / 2)
            .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
            .rotationEffect(.degrees(title == "from" ? 0 : 180))
    }

    var fromToChain: some View {
        Button {
            showNetworkSelectSheet = true
        } label: {
            SwapFromToChain(chain: selectedChain)
        }
    }

    var fromToCoin: some View {
        Button {
            showCoinSelectSheet = true
        } label: {
            fromToCoinLabel
        }
    }

    var fromToCoinLabel: some View {
        SwapFromToCoin(coin: coin)
    }

    var fromToAmountField: some View {
        Group {
            SwapCryptoAmountTextField(amount: $amount) { oldValue, newValue in
                if title=="from" {
                    // A multi-character jump (paste, autofill, or clearing the
                    // field to a value) is a discrete action — fetch immediately
                    // instead of waiting out the keystroke debounce. Single-char
                    // edits stay debounced for free typing.
                    let immediate = abs(newValue.count - oldValue.count) > 1
                    detailsViewModel.updateFromAmount(
                        vault: vault,
                        referredCode: referredViewModel.savedReferredCode,
                        immediate: immediate
                    )
                    detailsViewModel.showAllPercentageButtons = true
                }
            }
            .disabled(title=="to")
        }
        // The "to" amount is never skeletoned: it always carries a value — the
        // `~`-indicative estimate while the quote loads, replaced by the firm
        // amount once it lands. Only the swap-details summary (provider, fees)
        // shows the loading skeleton.
        .animation(.easeInOut(duration: 0.25), value: amount)
    }

    var fiatBalance: some View {
        Text(fiatAmount.formatToFiat(includeCurrencySymbol: true))
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(isFiatVisible() ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: fiatAmount)
    }

    private func isFiatVisible() -> Bool {
        !amount.isEmpty && amount != "0"
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
