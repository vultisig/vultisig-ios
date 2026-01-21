//
//  FunctionCallCustom.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/05/24.
//

import SwiftUI
import Foundation
import Combine

class FunctionCallCustom: FunctionCallAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil

    @Published var amount: Decimal = 0.0
    @Published var custom: String = ""

    // Token selection
    @Published var tokens: [IdentifiableString] = []
    @Published var tokenValid: Bool = false
    @Published var selectedToken: IdentifiableString = .init(value: NSLocalizedString("selectToken", comment: "Select Token placeholder"))
    @Published var balanceLabel: String = NSLocalizedString("amountSelectToken", comment: "Amount label when no token selected")

    // Internal
    @Published var amountValid: Bool = false
    @Published var customValid: Bool = false

    @ObservedObject var tx: SendTransaction
    private var vault: Vault

    private var cancellables = Set<AnyCancellable>()

    var addressFields: [String: String] {
        get { [:] }
        set { }
    }

    required init(tx: SendTransaction, vault: Vault) {
        self.tx = tx
        self.vault = vault
    }

    init(custom: String, tx: SendTransaction, vault: Vault) {
        self.custom = custom
        self.tx = tx
        self.vault = vault
    }

    func initialize() {
        setupValidation()
        loadTokens()
        preSelectToken()
    }

    private func loadTokens() {
        // Load tokens based on the transaction's chain
        switch tx.coin.chain {
        case .thorChain:
            // Load THORChain tokens from vault: RUNE, RUJI, TCY
            let thorchainCoins = vault.coins.filter { $0.chain == .thorChain }

            for coin in thorchainCoins {
                let ticker = coin.ticker.uppercased()
                // Add RUNE (native), RUJI, and TCY
                if ticker == "RUNE" || ticker == "RUJI" || ticker == "TCY" {
                    tokens.append(.init(value: ticker))
                }
            }

            // If no tokens found, at least add RUNE
            if tokens.isEmpty {
                tokens.append(.init(value: "RUNE"))
            }

        case .mayaChain:
            // Load CACAO from TokensStore filtered by MayaChain
            let mayaChainTokens = TokensStore.TokenSelectionAssets.filter { $0.chain == .mayaChain }
            for token in mayaChainTokens {
                let ticker = token.ticker.uppercased()
                // Add CACAO (native token) and MAYA
                if ticker == "CACAO" || ticker == "MAYA" {
                    tokens.append(.init(value: ticker))
                }
            }

        default:
            break
        }
    }

    private func preSelectToken() {
        // Pre-select the current transaction coin if it's in the list
        let currentTicker = tx.coin.ticker.uppercased()
        if let match = tokens.first(where: { $0.value == currentTicker }) {
            selectedToken = match
            tokenValid = true
            updateBalanceLabel()
        }
    }

    var selectedVaultCoin: Coin? {
        let ticker = selectedToken.value.lowercased()

        for coin in vault.coins {
            // Check THORChain for RUNE, RUJI, TCY
            if coin.chain == .thorChain && coin.ticker.lowercased() == ticker {
                return coin
            }
            // Check MayaChain for MAYA
            if coin.chain == .mayaChain && coin.ticker.lowercased() == ticker {
                return coin
            }
        }

        return nil
    }

    func updateBalanceLabel() {
        if let coin = selectedVaultCoin {
            let balance = coin.balanceDecimal.formatForDisplay()
            balanceLabel = String(format: NSLocalizedString("amountBalance", comment: "Amount with balance"), balance, coin.ticker.uppercased())
        } else {
            balanceLabel = NSLocalizedString("amountSelectToken", comment: "Amount label when no token selected")
        }
    }

    private func setupValidation() {
        Publishers.CombineLatest3($amountValid, $customValid, $tokenValid)
            .map { $0 && $1 && $2 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        return self.custom
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }

    func getView() -> AnyView {
        AnyView(FunctionCallCustomView(viewModel: self).onAppear {
            self.initialize()
        })
    }
}

private struct FunctionCallCustomView: View {
    @ObservedObject var viewModel: FunctionCallCustom

    var body: some View {
        VStack {
            // Token selection dropdown
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
                onSelect: { token in
                    viewModel.selectedToken = token
                    viewModel.tokenValid = token.value.lowercased() != NSLocalizedString("selectToken", comment: "").lowercased()

                    if let coin = viewModel.selectedVaultCoin {
                        withAnimation {
                            viewModel.updateBalanceLabel()

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
                ),
                isOptional: true
            )
            .id("field-\(viewModel.selectedToken.value)")

            StyledTextField(
                placeholder: NSLocalizedString("customMemo", comment: "Custom Memo placeholder"),
                text: Binding(
                    get: { viewModel.custom },
                    set: { viewModel.custom = $0 }
                ),
                maxLengthSize: Int.max,
                isValid: Binding(
                    get: { viewModel.customValid },
                    set: { viewModel.customValid = $0 }
                )
            )
        }
    }
}
