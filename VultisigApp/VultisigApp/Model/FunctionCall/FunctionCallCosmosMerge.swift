//
//  TransactionMemoCosmosMerge.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

/**
 
 3) THORCHAIN - FUNCTION: “EXECUTE CONTRACT”
 
 UI Elements:
 •    Dropdown: Select action (only one for now: "RUJI MERGE")
 •    Amount Field: Enter amount to deposit
 
 Action:
 → Call the RUJI Merge smart contract to deposit the specified amount
 
 */

class FunctionCallCosmosMerge: ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var destinationAddress: String = ""
    @Published var txMemo: String = ""
    
    @Published var amountValid: Bool = false
    @Published var txMemoValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    
    @Published var tokens: [IdentifiableString] = []
    @Published var tokenValid: Bool = false
    @Published var selectedToken: IdentifiableString = .init(value: "Select the token to be merged")
    
    @Published var balanceLabel: String = "( Select a token )"
    
    @ObservedObject var tx: SendTransaction
    
    private var vault: Vault
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, transactionMemoViewModel: TransactionMemoViewModel, vault: Vault
    ) {
        self.tx = tx
        self.vault = vault
        
        setupValidation()
        
        let coinsInVault: Set<String> = Set(vault.coins.filter { $0.chain == tx.coin.chain }.map {
            let normalized = $0.ticker.lowercased()
            return normalized
        })
        
        for token in tokensToMerge {
            let normalizedToken = token.denom.lowercased().replacingOccurrences(of: "thor.", with: "")
            if coinsInVault.contains(normalizedToken) {
                tokens.append(.init(value: token.denom.uppercased()))
            }
        }
        
        if let match = tokensToMerge.first(where: {
            $0.denom.lowercased() == "thor.\(tx.coin.ticker.lowercased())"
        }) {
            selectedToken = .init(value: match.denom.uppercased())
            tokenValid = true
            destinationAddress = match.wasmContractAddress
            if let coin = selectedVaultCoin {
                amount = coin.balanceDecimal
                balanceLabel = "Amount ( Balance: \(amount.formatDecimalToLocale() ?? "0") \(coin.ticker.uppercased()) )"
            }
        }
        
        if tx.coin.isNativeToken {
            self.amount = 0.0
        } else  {
            self.amount = tx.coin.balanceDecimal
        }
        
    }
    
    private var selectedVaultCoin: Coin? {
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
            let balance = coin.balanceDecimal.formatDecimalToLocale() ?? "0"
            return "Amount ( Balance: \(balance) \(coin.ticker.uppercased()) )"
        } else {
            return "Amount ( Select a token )"
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
        AnyView(VStack {
            
            GenericSelectorDropDown(
                items: Binding(
                    get: { self.tokens },
                    set: { self.tokens = $0 }
                ),
                selected: Binding(
                    get: { self.selectedToken },
                    set: { self.selectedToken = $0 }
                ),
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    self.selectedToken = asset
                    self.tokenValid = asset.value.lowercased() != "select the token to be merged"
                    self.destinationAddress = self.tokensToMerge.first {
                        $0.denom.lowercased() == asset.value.lowercased()
                    }?.wasmContractAddress ?? ""
                    
                    if let coin = self.selectedVaultCoin {
                        
                        withAnimation {
                            self.balanceLabel = "Amount ( Balance: \(coin.balanceDecimal.formatDecimalToLocale() ?? "0") \(coin.ticker.uppercased()) )"
                            self.amount = coin.balanceDecimal
                            
                            self.objectWillChange.send()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.tx.coin = coin
                                self.objectWillChange.send()
                            }
                        }
                    } else {
                        self.balanceLabel = "Amount ( Select a token )"
                        self.objectWillChange.send()
                    }
                }
            )
            
            StyledFloatingPointField(
                placeholder: Binding(
                    get: { self.balanceLabel },
                    set: {
                        self.balanceLabel = $0
                        DispatchQueue.main.async {
                            self.objectWillChange.send()
                        }
                    }
                ),
                value: Binding(
                    get: { self.amount },
                    set: {
                        self.amount = $0
                        DispatchQueue.main.async {
                            self.objectWillChange.send()
                        }
                    }
                ),
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                )
            )
            .id("field-\(self.balanceLabel)-\(self.amount)")
        })
    }
    
    struct TokenMergeInfo: Codable {
        let denom: String
        let wasmContractAddress: String
    }
    
    private let tokensToMerge: [TokenMergeInfo] = [
        TokenMergeInfo(denom: "thor.kuji", wasmContractAddress: "thor14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9s3p2nzy"),
        TokenMergeInfo(denom: "thor.rkuji", wasmContractAddress: "thor1yyca08xqdgvjz0psg56z67ejh9xms6l436u8y58m82npdqqhmmtqrsjrgh"),
        TokenMergeInfo(denom: "thor.fuzn", wasmContractAddress: "thor1suhgf5svhu4usrurvxzlgn54ksxmn8gljarjtxqnapv8kjnp4nrsw5xx2d"),
        TokenMergeInfo(denom: "thor.nstk", wasmContractAddress: "thor1cnuw3f076wgdyahssdkd0g3nr96ckq8cwa2mh029fn5mgf2fmcmsmam5ck"),
        TokenMergeInfo(denom: "thor.wink", wasmContractAddress: "thor1yw4xvtc43me9scqfr2jr2gzvcxd3a9y4eq7gaukreugw2yd2f8tsz3392y"),
        TokenMergeInfo(denom: "thor.lvn", wasmContractAddress: "thor1ltd0maxmte3xf4zshta9j5djrq9cl692ctsp9u5q0p9wss0f5lms7us4yf")
    ]
}
