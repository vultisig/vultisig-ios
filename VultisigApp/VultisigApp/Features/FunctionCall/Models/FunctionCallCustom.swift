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

    init(coin: Coin, vault: Vault) {
        let initialPlaceholder = "selectToken".localized
        self.placeholder = initialPlaceholder
        self.vault = vault
        self.selectedToken = .init(value: initialPlaceholder)
        self.balanceLabel = "amountSelectToken".localized

        loadTokens(for: coin.chain)
        preSelectToken(matching: coin)
    }

    private func loadTokens(for chain: Chain) {
        switch chain {
        case .thorChain:
            let chainCoins = vault.coins.filter { $0.chain == .thorChain }
            for coin in chainCoins {
                let ticker = coin.ticker.uppercased()
                if ticker == "RUNE" || ticker == "RUJI" || ticker == "TCY" {
                    tokens.append(.init(value: ticker))
                }
            }
            if tokens.isEmpty {
                tokens.append(.init(value: "RUNE"))
            }
        case .mayaChain:
            let chainCoins = vault.coins.filter { $0.chain == .mayaChain }
            for coin in chainCoins {
                let ticker = coin.ticker.uppercased()
                if ticker == "CACAO" || ticker == "MAYA" || ticker == "AZTEC" {
                    tokens.append(.init(value: ticker))
                }
            }
            if tokens.isEmpty {
                tokens.append(.init(value: "CACAO"))
            }
        default:
            break
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
        for coin in vault.coins {
            if coin.chain == .thorChain && coin.ticker.lowercased() == ticker {
                return coin
            }
            if coin.chain == .mayaChain && coin.ticker.lowercased() == ticker {
                return coin
            }
        }
        return nil
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
