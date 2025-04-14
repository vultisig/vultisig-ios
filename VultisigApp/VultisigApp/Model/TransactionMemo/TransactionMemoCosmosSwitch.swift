//
//  TransactionMemoCosmosIBC.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

/**

 2) COSMOS - FUNCTION: “SWITCH THORCHAIN”

 UI Elements:
     •    Address Field:
     •    Prefilled with the user’s THORChain address
     •    Allow manual override
     •    Amount Field: Enter amount to switch

 Action:
 → Send MsgSend from COSMOS to THORChain vault
 → Include memo: SWITCH:<thorAddress>
 
 */

class TransactionMemoCosmosSwitch: TransactionMemoAddressable, ObservableObject {
    @Published var amount: Double = 0.0
    @Published var destinationAddress: String = "cosmos144za3huzmfl3k6hge487a6gnu06vwk6t2hfk53"
    @Published var thorAddress: String = ""
    
    @Published var amountValid: Bool = false
    @Published var destinationAddressValid: Bool = true
    @Published var thorchainAddressValid: Bool = false
    
    @Published var isTheFormValid: Bool = false
    
    
    private var tx: SendTransaction
    private var vault: Vault
    
    var addressFields: [String: String] {
        get {
            let fields = ["destinationAddress": destinationAddress, "thorchainAddress": thorAddress]
            return fields
        }
        set {
            if let value = newValue["destinationAddress"] {
                destinationAddress = value
            }
            if let value = newValue["thorchainAddress"] {
                thorAddress = value
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, transactionMemoViewModel: TransactionMemoViewModel, vault: Vault
    ) {
        self.tx = tx
        self.vault = vault
        
        let thorchainCoin = self.vault.coins.first { $0.chain == .thorChain && $0.isNativeToken }
        if let thorchainCoin = thorchainCoin {
            self.thorAddress = thorchainCoin.address
            self.thorchainAddressValid = true
        }
        
        setupValidation()
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.description
        
        self.amount = Double(balance) ?? 0.0
        
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    private func setupValidation() {
        Publishers.CombineLatest3($amountValid, $destinationAddressValid, $thorchainAddressValid)
            .map { $0 && $1 && $2 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        let memo = "SWITCH:\(self.thorAddress)"
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", self.destinationAddress)
        dict.set("thorchainAddress", self.thorAddress)
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
                        
            TransactionMemoAddressTextField(
                memo: self,
                addressKey: "destinationAddress",
                isAddressValid: Binding(
                    get: { self.destinationAddressValid },
                    set: { self.destinationAddressValid = $0 }
                ),
            )
            
            TransactionMemoAddressTextField(
                memo: self,
                addressKey: "thorchainAddress",
                isAddressValid: Binding(
                    get: { self.thorchainAddressValid },
                    set: { self.thorchainAddressValid = $0 }
                ),
            )
            
            StyledFloatingPointField(
                placeholder: "Amount \(balance)",
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
}
