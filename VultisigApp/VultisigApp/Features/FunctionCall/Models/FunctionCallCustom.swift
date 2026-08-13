//
//  FunctionCallCustom.swift
//  VultisigApp
//
//  Custom memo sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — owns token selection, amount, and
//  free-form memo directly. The matching `CustomFormView` is
//  co-located in this file. Cross-mutator: writes the screen-owned
//  `selectedCoin` through a `@Binding<Coin>` when the user picks a
//  different token from the dropdown.
//

import BigInt
import Foundation
import SwiftUI

@Observable
@MainActor
final class FunctionCallCustom {
    var amount: Decimal = 0.0
    var custom: String = ""

    var tokens: [IdentifiableString] = []
    var selectedToken: IdentifiableString
    var balanceLabel: String
    var customErrorMessage: String?

    @ObservationIgnored private let placeholder: String
    @ObservationIgnored private let vault: Vault
    /// The chain this form runs on. Token lookup is scoped to it so a ticker
    /// can only ever resolve to a coin on the chain the memo is deposited to.
    @ObservationIgnored private let chain: Chain

    init(coin: Coin, vault: Vault) {
        let initialPlaceholder = "selectToken".localized
        self.placeholder = initialPlaceholder
        self.vault = vault
        self.chain = coin.chain
        self.selectedToken = .init(value: initialPlaceholder)
        self.balanceLabel = "amountSelectToken".localized

        loadTokens(for: coin.chain)
        preSelectToken(matching: coin)
    }

    private func loadTokens(for chain: Chain) {
        switch chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            // The test networks are listed with mainnet: they run the same
            // `MsgDeposit`, and leaving them out left the token list empty,
            // which made `isTokenSelected` false and the form permanently
            // unsubmittable — an operation the app offered but could not send.
            appendTokens(on: chain, tickers: ["RUNE", "RUJI", "TCY"], fallback: "RUNE")
        case .mayaChain:
            appendTokens(on: chain, tickers: ["CACAO", "MAYA", "AZTEC"], fallback: "CACAO")
        default:
            break
        }
    }

    private func appendTokens(on chain: Chain, tickers: [String], fallback: String) {
        for coin in vault.coins where coin.chain == chain {
            let ticker = coin.ticker.uppercased()
            if tickers.contains(ticker) {
                tokens.append(.init(value: ticker))
            }
        }
        if tokens.isEmpty {
            tokens.append(.init(value: fallback))
        }
    }

    private func preSelectToken(matching coin: Coin) {
        let currentTicker = coin.ticker.uppercased()
        if let match = tokens.first(where: { $0.value == currentTicker }) {
            selectedToken = match
            updateBalanceLabel()
        }
    }

    var isTokenSelected: Bool {
        selectedToken.value.lowercased() != placeholder.lowercased()
    }

    func selectedVaultCoin() -> Coin? {
        let ticker = selectedToken.value.lowercased()
        // Scoped to this form's own chain rather than to the THOR/Maya pair:
        // the picked ticker becomes the screen's active coin, so resolving it
        // on any chain but this one would deposit the memo against the wrong
        // asset. It also lets the test networks resolve their own coins.
        return vault.coins.first { $0.chain == chain && $0.ticker.lowercased() == ticker }
    }

    func updateBalanceLabel() {
        if let coin = selectedVaultCoin() {
            let balance = coin.balanceDecimal.formatForDisplay()
            balanceLabel = String(format: "amountBalance".localized, balance, coin.ticker.uppercased())
        } else {
            balanceLabel = "amountSelectToken".localized
        }
    }

    /// Submit-time validity gate. Requires the active coin so the
    /// optional amount stays within balance — the no-arg `isTheFormValid`
    /// only checked token + memo and let an over-balance amount through.
    /// Amount is optional (memo-only custom calls send zero), so zero is
    /// accepted; any positive amount must not exceed the coin balance.
    func isFormValid(for coin: Coin) -> Bool {
        isTokenSelected &&
        !custom.isEmpty &&
        amount >= 0 &&
        amount <= coin.balanceDecimal
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        custom
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", toString())
        return dict
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt
    ) -> SendTransaction {
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct CustomFormView: View {
    @Bindable var model: FunctionCallCustom
    @Binding var selectedCoin: Coin

    var body: some View {
        VStack {
            GenericSelectorDropDown(
                items: $model.tokens,
                selected: $model.selectedToken,
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { token in
                    model.selectedToken = token
                    if let coin = model.selectedVaultCoin() {
                        model.updateBalanceLabel()
                        selectedCoin = coin
                    } else {
                        model.balanceLabel = "amountSelectToken".localized
                    }
                }
            )

            StyledFloatingPointField(
                label: model.balanceLabel,
                placeholder: model.balanceLabel,
                value: $model.amount,
                isValid: .constant(true),
                isOptional: true
            )
            .id("field-\(model.selectedToken.value)")

            StyledTextField(
                placeholder: "customMemo".localized,
                text: $model.custom,
                maxLengthSize: Int.max,
                isValid: .constant(true)
            )
        }
    }
}
