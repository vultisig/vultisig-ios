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

class TransactionMemoCosmosMerge: ObservableObject {
    @Published var amount: Double = 0.0
    @Published var destinationAddress: String = ""
    @Published var txMemo: String = ""
    
    @Published var amountValid: Bool = false
    @Published var txMemoValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    
    @Published var tokens: [IdentifiableString] = []
    @Published var tokenValid: Bool = false
    @Published var selectedToken: IdentifiableString = .init(value: "Select the token to be merged")
    
    private var tx: SendTransaction
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, transactionMemoViewModel: TransactionMemoViewModel
    ) {
        self.tx = tx
        setupValidation()
        
        for token in tokensToMerge {
            tokens.append(.init(value: "\(token.denom.uppercased())"))
        }
    }
    
    //The balance is not correct since it should be the balance of the token not the RUNE balance
    var balance: String {
        let balance = tx.coin.balanceDecimal.description
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
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
                items: .constant(tokens),
                selected: Binding(
                    get: { self.selectedToken },
                    set: { self.selectedToken = $0 }
                ),
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    self.selectedToken = asset
                    self.tokenValid = asset.value.lowercased() != "Select the token to be merged".lowercased()
                    self.destinationAddress = self.tokensToMerge.first { $0.denom.lowercased() == asset.value.lowercased() }?.wasmContractAddress ?? ""
                }
            )
            
            StyledFloatingPointField(
                //placeholder: "Amount \(balance)",
                placeholder: "Amount",
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                format: .number,
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                )
            )
        })
    }
    
    struct TokenMergeInfo: Codable {
        let denom: String
        let wasmContractAddress: String
    }
    
    private let tokensToMerge: [TokenMergeInfo] =
    [
        TokenMergeInfo(denom: "thor.kuji", wasmContractAddress: "thor14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9s3p2nzy"),
        TokenMergeInfo(denom: "thor.rkuji", wasmContractAddress: "thor1yyca08xqdgvjz0psg56z67ejh9xms6l436u8y58m82npdqqhmmtqrsjrgh"),
        TokenMergeInfo(denom: "thor.fuzn", wasmContractAddress: "thor1suhgf5svhu4usrurvxzlgn54ksxmn8gljarjtxqnapv8kjnp4nrsw5xx2d"),
        TokenMergeInfo(denom: "thor.nstk", wasmContractAddress: "thor1cnuw3f076wgdyahssdkd0g3nr96ckq8cwa2mh029fn5mgf2fmcmsmam5ck"),
        TokenMergeInfo(denom: "thor.wink", wasmContractAddress: "thor1yw4xvtc43me9scqfr2jr2gzvcxd3a9y4eq7gaukreugw2yd2f8tsz3392y"),
        TokenMergeInfo(denom: "thor.lvn", wasmContractAddress: "thor1ltd0maxmte3xf4zshta9j5djrq9cl692ctsp9u5q0p9wss0f5lms7us4yf")
    ]
}
