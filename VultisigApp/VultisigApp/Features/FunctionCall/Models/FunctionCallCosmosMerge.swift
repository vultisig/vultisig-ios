//
//  FunctionCallCosmosMerge.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

/**
 
 3) THORCHAIN - FUNCTION: "EXECUTE CONTRACT"
 
 UI Elements:
 •    Dropdown: Select action (only one for now: "RUJI MERGE")
 •    Amount Field: Enter amount to deposit
 
 Action:
 → Call the RUJI Merge smart contract to deposit the specified amount
 
 */

class FunctionCallCosmosMerge: ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var destinationAddress: String = ""
    @Published var fnCall: String = ""

    @Published var amountValid: Bool = false
    @Published var fnCallValid: Bool = true

    @Published var isTheFormValid: Bool = false

    @Published var tokens: [IdentifiableString] = []
    @Published var tokenValid: Bool = false
    @Published var selectedToken: IdentifiableString = .init(value: NSLocalizedString("selectTokenToMerge", comment: ""))

    @Published var balanceLabel: String = NSLocalizedString("amountSelectToken", comment: "")

    @ObservedObject var tx: SendTransaction

    private var vault: Vault

    private var cancellables = Set<AnyCancellable>()

    required init(
        tx: SendTransaction, vault: Vault
    ) {
        self.tx = tx
        self.vault = vault

        if tx.coin.isNativeToken {
            self.amount = 0.0
        } else {
            self.amount = tx.coin.balanceDecimal
        }
    }

    func initialize() {
        setupValidation()
        loadTokens()
        preSelectToken()
    }

    private func loadTokens() {
        let coinsInVault: Set<String> = Set(vault.coins.filter { $0.chain == tx.coin.chain }.map {
            let normalized = $0.ticker.lowercased()
            return normalized
        })

        for token in ThorchainMergeTokens.tokensToMerge {
            let normalizedToken = token.denom.lowercased().replacingOccurrences(of: "thor.", with: "")
            if coinsInVault.contains(normalizedToken) {
                tokens.append(.init(value: token.denom.uppercased()))
            }
        }
    }

    private func preSelectToken() {
        if let match = ThorchainMergeTokens.tokensToMerge.first(where: {
            $0.denom.lowercased() == "thor.\(tx.coin.ticker.lowercased())"
        }) {
            selectedToken = .init(value: match.denom.uppercased())
            tokenValid = true
            destinationAddress = match.wasmContractAddress
            if let coin = selectedVaultCoin {
                amount = coin.balanceDecimal
                balanceLabel = String(format: NSLocalizedString("amountBalance", comment: ""), amount.formatForDisplay(), coin.ticker.uppercased())
            }
        }
    }

    var selectedVaultCoin: Coin? {
        let ticker = selectedToken.value
            .lowercased()
            .replacingOccurrences(of: "thor.", with: "")

        for coin in vault.coins {
            if coin.chain == tx.coin.chain && coin.ticker.lowercased() == ticker {
                return coin
            }
        }

        return nil
    }

    var balance: String {
        if let coin = selectedVaultCoin {
            let balance = coin.balanceDecimal.formatForDisplay()
            return String(format: NSLocalizedString("amountBalance", comment: ""), balance, coin.ticker.uppercased())
        } else {
            return NSLocalizedString("amountSelectToken", comment: "")
        }
    }

    private func setupValidation() {
        Publishers.CombineLatest($amountValid, $tokenValid)
            .map { $0 && $1 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        let memo = "merge:\(selectedToken.value)"
        return memo
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", self.destinationAddress)
        dict.set("memo", self.toString())
        return dict
    }

    func getView() -> AnyView {
        AnyView(FunctionCallCosmosMergeView(viewModel: self).onAppear {
            self.initialize()
        })
    }
}

private struct FunctionCallCosmosMergeView: View {
    @ObservedObject var viewModel: FunctionCallCosmosMerge

    var body: some View {
        VStack {

            GenericSelectorDropDown(
                items: Binding(
                    get: { viewModel.tokens },
                    set: { viewModel.tokens = $0 }
                ),
                selected: Binding(
                    get: { viewModel.selectedToken },
                    set: { viewModel.selectedToken = $0 }
                ),
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    viewModel.selectedToken = asset
                    viewModel.tokenValid = asset.value.lowercased() != NSLocalizedString("selectTokenToMerge", comment: "").lowercased()
                    viewModel.destinationAddress = ThorchainMergeTokens.tokensToMerge.first {
                        $0.denom.lowercased() == asset.value.lowercased()
                    }?.wasmContractAddress ?? ""

                    if let coin = viewModel.selectedVaultCoin {

                        withAnimation {
                            viewModel.balanceLabel = String(format: NSLocalizedString("amountBalance", comment: ""), coin.balanceDecimal.formatForDisplay(), coin.ticker.uppercased())
                            viewModel.amount = coin.balanceDecimal

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                viewModel.tx.coin = coin
                                viewModel.objectWillChange.send()
                            }
                        }
                    } else {
                        viewModel.balanceLabel = NSLocalizedString("amountSelectToken", comment: "")
                        viewModel.objectWillChange.send()
                    }
                }
            )

            StyledFloatingPointField(
                label: viewModel.balanceLabel,
                placeholder: viewModel.balanceLabel,
                value: Binding(
                    get: { viewModel.amount },
                    set: {
                        viewModel.amount = $0
                        DispatchQueue.main.async {
                            viewModel.objectWillChange.send()
                        }
                    }
                ),
                isValid: Binding(
                    get: { viewModel.amountValid },
                    set: { viewModel.amountValid = $0 }
                )
            )
            .id("field-\(viewModel.selectedToken.value)")
        }
    }
}
