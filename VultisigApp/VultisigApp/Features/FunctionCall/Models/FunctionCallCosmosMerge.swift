//
//  FunctionCallCosmosMerge.swift
//  VultisigApp
//
//  RUJI MERGE sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — owns token selection + amount +
//  derived contract address directly. Cross-mutator: writes
//  `selectedCoin` through a `@Binding<Coin>` from the token dropdown.
//

import BigInt
import Foundation
import SwiftUI

/*
 3) THORCHAIN - FUNCTION: "EXECUTE CONTRACT"

 UI Elements:
 • Dropdown: Select action (only one for now: "RUJI MERGE")
 • Amount Field: Enter amount to deposit

 Action:
 → Call the RUJI Merge smart contract to deposit the specified amount
*/

@Observable
@MainActor
final class FunctionCallCosmosMerge {
    var amount: Decimal = 0.0
    var destinationAddress: String = ""
    var tokens: [IdentifiableString] = []
    var selectedToken: IdentifiableString
    var balanceLabel: String

    @ObservationIgnored private let tokenPlaceholder: String
    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private let sourceChain: Chain
    @ObservationIgnored private let sourceTicker: String
    @ObservationIgnored private let sourceIsNative: Bool

    init(coin: Coin, vault: Vault) {
        let placeholder = "selectTokenToMerge".localized
        self.tokenPlaceholder = placeholder
        self.vault = vault
        self.sourceChain = coin.chain
        self.sourceTicker = coin.ticker
        self.sourceIsNative = coin.isNativeToken
        self.selectedToken = .init(value: placeholder)
        self.balanceLabel = "amountSelectToken".localized

        if coin.isNativeToken {
            self.amount = 0.0
        } else {
            self.amount = coin.balanceDecimal
        }

        loadTokens()
        preSelectToken()
    }

    private func loadTokens() {
        let coinsInVault: Set<String> = Set(vault.coins.filter { $0.chain == sourceChain }.map { $0.ticker.lowercased() })
        for token in ThorchainMergeTokens.tokensToMerge {
            let normalized = token.denom.lowercased().replacingOccurrences(of: "thor.", with: "")
            if coinsInVault.contains(normalized) {
                tokens.append(.init(value: token.denom.uppercased()))
            }
        }
    }

    private func preSelectToken() {
        if let match = ThorchainMergeTokens.tokensToMerge.first(where: {
            $0.denom.lowercased() == "thor.\(sourceTicker.lowercased())"
        }) {
            selectedToken = .init(value: match.denom.uppercased())
            destinationAddress = match.wasmContractAddress
            if let coin = selectedVaultCoin() {
                amount = coin.balanceDecimal
                balanceLabel = String(format: "amountBalance".localized, amount.formatForDisplay(), coin.ticker.uppercased())
            }
        }
    }

    func selectedVaultCoin() -> Coin? {
        let ticker = selectedToken.value
            .lowercased()
            .replacingOccurrences(of: "thor.", with: "")
        for coin in vault.coins where coin.chain == sourceChain && coin.ticker.lowercased() == ticker {
            return coin
        }
        return nil
    }

    var isTokenSelected: Bool {
        selectedToken.value.lowercased() != tokenPlaceholder.lowercased()
    }

    /// Submit-time validity gate. Requires the active coin so the
    /// amount-against-balance check rides in the same predicate the
    /// Continue button reads. Merge cross-mutates the active coin via
    /// the token dropdown, so the screen-side `selectedCoin` is the
    /// correct source of truth for the balance bound.
    func isFormValid(for coin: Coin) -> Bool {
        isTokenSelected &&
        amount > 0 &&
        amount <= coin.balanceDecimal
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        "merge:\(selectedToken.value)"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", destinationAddress)
        dict.set("memo", toString())
        return dict
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        _ = isFastVault
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            toAddress: destinationAddress,
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .thorMerge,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct CosmosMergeFormView: View {
    @Bindable var model: FunctionCallCosmosMerge
    @Binding var selectedCoin: Coin

    var body: some View {
        VStack {
            GenericSelectorDropDown(
                items: $model.tokens,
                selected: $model.selectedToken,
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    model.selectedToken = asset
                    model.destinationAddress = ThorchainMergeTokens.tokensToMerge.first {
                        $0.denom.lowercased() == asset.value.lowercased()
                    }?.wasmContractAddress ?? ""

                    if let coin = model.selectedVaultCoin() {
                        model.balanceLabel = String(format: "amountBalance".localized, coin.balanceDecimal.formatForDisplay(), coin.ticker.uppercased())
                        model.amount = coin.balanceDecimal
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
                isValid: .constant(true)
            )
            .id("field-\(model.selectedToken.value)")
        }
    }
}
