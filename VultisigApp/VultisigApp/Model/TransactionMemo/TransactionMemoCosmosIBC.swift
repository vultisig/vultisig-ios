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
 
 1) KUJIRA - FUNCTION: “IBC SEND”
 
 UI Elements:
 •    Dropdown: Select destination chain (IBC compatible)
 •    Address Field:
 •    Prefilled with the user’s destination chain address :: TODO
 •    Allow manual override
 •    Amount Field: Enter amount to send
 •    Memo Field (Optional): Enter memo if needed
 
 Action:
 → Perform IBC transfer from KUJIRA to the selected destination chain.
 
 */

class TransactionMemoCosmosIBC: TransactionMemoAddressable, ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var destinationAddress: String = ""
    @Published var txMemo: String = ""
    
    @Published var amountValid: Bool = false
    @Published var txMemoValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    
    @Published var chains: [IdentifiableString] = []
    @Published var chainValid: Bool = false
    @Published var selectedChain: IdentifiableString = .init(value: "Select the destination chain")
    
    @Published var selectedChainObject: Chain? = nil
    
    private var tx: SendTransaction
    private var vault: Vault
    
    var addressFields: [String: String] {
        get {
            let fields = ["destinationAddress": destinationAddress]
            return fields
        }
        set {
            if let value = newValue["destinationAddress"] {
                destinationAddress = value
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, transactionMemoViewModel: TransactionMemoViewModel, vault: Vault
    ) {
        self.tx = tx
        self.vault = vault
        setupValidation()
        
        let cosmosChains: [Chain] = Chain.allCases.filter { $0.chainType == .Cosmos && $0 != tx.coin.chain && (!$0.name.lowercased().contains("terra")) }
        
        for chain in cosmosChains {
            chains.append(.init(value: "\(chain.name) \(chain.ticker)"))
        }
                
        getChainAddress()
        
        self.amount = tx.coin.balanceDecimal
        
    }
    
    private func getChainAddress() -> Void {
        
        if selectedChainObject != nil {
            let chainAddress = self.vault.coins.first { $0.chain == selectedChainObject && $0.isNativeToken }
            if let chainAddress = chainAddress {
                self.destinationAddress = chainAddress.address
            } else {
                self.destinationAddress = ""
            }
        }
        
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.description
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    private func setupValidation() {
        Publishers.CombineLatest($amountValid, $chainValid)
            .map { $0 && $1 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "\(self.selectedChainObject?.name ?? ""):\(self.tx.coin.chain.ibcChannel(to: selectedChainObject) ?? ""):\(self.destinationAddress)"
        if txMemo.isEmpty == false {
            memo += ":\(self.txMemo)"
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationChain", self.selectedChainObject?.name ?? "")
        dict.set("destinationChannel", self.tx.coin.chain.ibcChannel(to: selectedChainObject) ?? "")
        dict.set("destinationAddress", self.destinationAddress)
        dict.set("transferMemo", self.txMemo)
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            
            GenericSelectorDropDown(
                items: .constant(chains),
                selected: Binding(
                    get: { self.selectedChain },
                    set: { self.selectedChain = $0 }
                ),
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    self.selectedChain = asset
                    self.chainValid = asset.value.lowercased() != "Select the destination chain".lowercased()
                    
                    let chainInfos = asset.value.split(separator: " ")
                    let chainName = chainInfos[0]
                    
                    self.selectedChainObject = Chain(name: chainName.description)
                    
                    self.getChainAddress()
                }
            )
            
            TransactionMemoAddressTextField(
                memo: self,
                addressKey: "destinationAddress",
                isAddressValid: .constant(true),
                chain: self.selectedChainObject
            ).id(self.selectedChainObject?.name ?? UUID().uuidString)
            
            StyledFloatingPointField(
                placeholder: Binding(
                    get: { "Amount \(self.balance)" },
                    set: { _ in }
                ),
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                )
            )
            StyledTextField(
                placeholder: "Memo",
                text: Binding(
                    get: { self.txMemo },
                    set: { self.txMemo = $0 }
                ),
                maxLengthSize: Int.max,
                isValid: Binding(
                    get: { self.txMemoValid },
                    set: { self.txMemoValid = $0 }
                ),
                isOptional: true
            )
            
        })
    }
}
