//
//  FunctionCallCosmosIBC.swift
//  VultisigApp
//
//  IBC transfer sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — owns destination address + chain +
//  amount + optional memo directly. The matching `CosmosIBCFormView`
//  is co-located in this file.
//

import BigInt
import Foundation
import SwiftUI

/*

 1) KUJIRA - FUNCTION: "IBC SEND"

 UI Elements:
 • Dropdown: Select destination chain (IBC compatible)
 • Address Field: prefilled with the user's destination chain address (manual override allowed)
 • Amount Field: Enter amount to send
 • Memo Field (Optional)

 Action:
 → Perform IBC transfer from KUJIRA to the selected destination chain.
*/

@Observable
@MainActor
final class FunctionCallCosmosIBC {
    var amount: Decimal = 0.0
    var destinationAddress: String = ""
    var fnCall: String = ""

    var chains: [IdentifiableString] = []
    var selectedChain: IdentifiableString
    var selectedChainObject: Chain?

    var addressError: String?
    var customErrorMessage: String?

    @ObservationIgnored private let chainPlaceholder: String
    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private let sourceChain: Chain
    @ObservationIgnored private let sourceTicker: String

    init(coin: Coin, vault: Vault) {
        let placeholder = "selectDestinationChain".localized
        self.chainPlaceholder = placeholder
        self.vault = vault
        self.sourceChain = coin.chain
        self.sourceTicker = coin.ticker
        self.selectedChain = .init(value: placeholder)
        self.amount = coin.balanceDecimal

        loadChains()
    }

    private func loadChains() {
        let cosmosChains: [Chain] = sourceChain.ibcTo.map { $0.destinationChain }
        for chain in cosmosChains {
            if sourceTicker == TokensStore.Token.kujiraLVN.ticker, sourceChain == .kujira { continue }
            chains.append(.init(value: "\(chain.name) \(chain.ticker)"))
        }
    }

    func updateDestinationAddress() {
        guard let selectedChainObject else {
            destinationAddress = ""
            return
        }
        if let chainCoin = vault.coins.first(where: { $0.chain == selectedChainObject && $0.isNativeToken }) {
            destinationAddress = chainCoin.address
        } else {
            destinationAddress = ""
        }
    }

    func balance(for coin: Coin) -> String {
        let balance = coin.balanceDecimal.description
        return String(format: "balanceInParentheses".localized, balance, coin.ticker.uppercased())
    }

    var isChainSelected: Bool {
        selectedChain.value.lowercased() != chainPlaceholder.lowercased()
    }

    var isTheFormValid: Bool {
        isChainSelected && amount > 0
    }

    func handle(addressResult: AddressResult?) {
        guard let addressResult else { return }
        destinationAddress = addressResult.address
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        var memo = "\(selectedChainObject?.name ?? ""):\(sourceChain.ibcChannel(to: selectedChainObject) ?? ""):\(destinationAddress)"
        if !fnCall.isEmpty {
            memo += ":\(fnCall)"
        }
        return memo
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationChain", selectedChainObject?.name ?? "")
        dict.set("destinationChannel", sourceChain.ibcChannel(to: selectedChainObject) ?? "")
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
            transactionType: .ibcTransfer,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct CosmosIBCFormView: View {
    @Bindable var model: FunctionCallCosmosIBC
    @Binding var selectedCoin: Coin

    var body: some View {
        VStack {
            GenericSelectorDropDown(
                items: .constant(model.chains),
                selected: $model.selectedChain,
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    model.selectedChain = asset
                    let parts = asset.value.split(separator: " ")
                    if let chainName = parts.first {
                        model.selectedChainObject = Chain(name: String(chainName))
                    }
                    model.updateDestinationAddress()
                }
            )

            AddressTextField(
                address: $model.destinationAddress,
                label: "destinationAddress".localized,
                coin: selectedCoin,
                error: $model.addressError
            ) { result in
                model.handle(addressResult: result)
            }
            .id(model.selectedChainObject?.name ?? UUID().uuidString)

            StyledFloatingPointField(
                label: "\("amount".localized) \(model.balance(for: selectedCoin))",
                placeholder: "enterAmount".localized,
                value: $model.amount,
                isValid: .constant(true)
            )

            StyledTextField(
                placeholder: "memoLabel".localized,
                text: $model.fnCall,
                maxLengthSize: Int.max,
                isValid: .constant(true),
                isOptional: true
            )
        }
    }
}
