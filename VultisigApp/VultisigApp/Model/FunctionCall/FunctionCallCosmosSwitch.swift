//
//  FunctionCallCosmosIBC.swift
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

class FunctionCallCosmosSwitch: FunctionCallAddressable, ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var destinationAddress: String = ""
    @Published var thorAddress: String = ""
    
    @Published var amountValid: Bool = false
    @Published var destinationAddressValid: Bool = false
    @Published var thorchainAddressValid: Bool = false
    
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    
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
    
    required init(tx: SendTransaction, vault: Vault) {
        self.tx = tx
        self.vault = vault
        self.amount = tx.coin.balanceDecimal
        
        let thorchainCoin = self.vault.coins.first { $0.chain == .thorChain && $0.isNativeToken }
        if let thorchainCoin = thorchainCoin {
            self.thorAddress = thorchainCoin.address
            self.thorchainAddressValid = true
        }
    }
    
    func initialize() {
        setupValidation()
        fetchInboundAddress()
    }
    
    private func fetchInboundAddress() {
        Task { @MainActor in
            let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
            if let match = addresses.first(where: { $0.chain.uppercased() == "GAIA" }) {
                let halted = match.halted
                let globalPaused = match.global_trading_paused
                let chainPaused = match.chain_trading_paused
                
                if halted || globalPaused || chainPaused {
                    print("Chain is halted or paused. Cannot proceed with switch.")
                    return
                }
                self.destinationAddress = match.address
                self.destinationAddressValid = true
                
            }
        }
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.description
        return String(format: NSLocalizedString("balanceInParentheses", comment: ""), balance, tx.coin.ticker.uppercased())
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
            
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "destinationAddress",
                isAddressValid: Binding(
                    get: { self.destinationAddressValid },
                    set: { self.destinationAddressValid = $0 }
                ),
                chain: tx.coin.chain
            )
            
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "thorchainAddress",
                isAddressValid: Binding(
                    get: { self.thorchainAddressValid },
                    set: { self.thorchainAddressValid = $0 }
                )
            )
            
            StyledFloatingPointField(
                label: "\(NSLocalizedString("amount", comment: "")) \(self.balance)",
                placeholder: NSLocalizedString("enterAmount", comment: ""),
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                )
            )
            
        }.onAppear {
            self.initialize()
        })
    }
}
