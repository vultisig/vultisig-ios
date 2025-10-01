//
//  FunctionCallLeave.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

class FunctionCallLeave: FunctionCallAddressable, ObservableObject {
    @Published var nodeAddress: String = ""
    
    // Internal
    @Published var nodeAddressValid: Bool = false
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    
    var addressFields: [String: String] {
        get {
            return ["nodeAddress": nodeAddress]
        }
        set {
            if let value = newValue["nodeAddress"] {
                nodeAddress = value
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var tx: SendTransaction?
    private var vault: Vault?
    private var functionCallViewModel: FunctionCallViewModel?
    
    required init() {
    }
    
    init(nodeAddress: String) {
        self.nodeAddress = nodeAddress
    }
    
    init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault) {
        self.tx = tx
        self.vault = vault
        self.functionCallViewModel = functionCallViewModel
    }
    
    func initialize() {
        // Ensure RUNE token is selected for LEAVE operations on THORChain
        if let tx = tx, let vault = vault, let functionCallViewModel = functionCallViewModel,
           tx.coin.chain == .thorChain && !tx.coin.isNativeToken && tx.coin.ticker.uppercased() != "TCY" {
            DispatchQueue.main.async {
                functionCallViewModel.setRuneToken(to: tx, vault: vault)
            }
        }
        setupValidation()
    }
    
    private func setupValidation() {
        $nodeAddressValid
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
        
        $nodeAddress
            .map { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .assign(to: \.nodeAddressValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "LEAVE:\(self.nodeAddress)"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "nodeAddress",
                isAddressValid: Binding(
                    get: { self.nodeAddressValid },
                    set: { self.nodeAddressValid = $0 }
                )
            )
        }.onAppear {
            self.initialize()
        })
    }
}
