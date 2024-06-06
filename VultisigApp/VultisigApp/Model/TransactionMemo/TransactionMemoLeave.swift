//
//  TransactionMemoLeave.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoLeave: TransactionMemoAddressable, ObservableObject {
    @Published var nodeAddress: String = ""
    
    // Internal
    @Published var nodeAddressValid: Bool = false
    @Published var isTheFormValid: Bool = false
    
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
    
    required init() {
        setupValidation()
    }
    
    init(nodeAddress: String) {
        self.nodeAddress = nodeAddress
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
            TransactionMemoAddressTextField(
                memo: self,
                addressKey: "nodeAddress",
                isAddressValid: Binding(
                    get: { self.nodeAddressValid },
                    set: { self.nodeAddressValid = $0 }
                )
            )
        })
    }
}
