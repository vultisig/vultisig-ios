//
//  TransactionMemoUnbond.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoUnbondMayaChain: TransactionMemoAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = false
    
    @Published var nodeAddress: String = ""
    @Published var amount: Double = 0.0
    
    // Internal
    @Published var nodeAddressValid: Bool = false
    @Published var amountValid: Bool = false

    @Published var selectedAsset: IdentifiableString = .init(value: "Asset")
    
    @Published var assets: [IdentifiableString] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    var addressFields: [String: String] {
        get {
            let fields = ["nodeAddress": nodeAddress]
            return fields
        }
        set {
            if let value = newValue["nodeAddress"] {
                nodeAddress = value
            }
        }
    }
    
    required init(assets: [String]) {
        setupValidation()
        self.assets = assets.map { IdentifiableString(value: $0) }
    }
    
    init(nodeAddress: String, amount: Double = 0.0, provider: String = "") {
        self.nodeAddress = nodeAddress
        self.amount = amount
        setupValidation()
    }
    
    private func setupValidation() {
        Publishers.CombineLatest($nodeAddressValid, $amountValid)
            .map { $0 && $1 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    var amountInUnits: String {
        let amountInSats = Int64(self.amount * pow(10, 8))
        return amountInSats.description
    }
    
    func toString() -> String {
        var memo = "UNBOND:\(self.selectedAsset.value):\(self.nodeAddress):\(amountInUnits)"
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("asset", self.selectedAsset.value)
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("Unbond amount", "\(self.amount)")
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            
            GenericSelectorDropDown(
                items: .constant(assets),
                selected: Binding(
                    get: { self.selectedAsset },
                    set: { self.selectedAsset = $0 }
                ),
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    self.selectedAsset = asset
                }
            )
            
            TransactionMemoAddressTextField(
                memo: self,
                addressKey: "nodeAddress",
                isAddressValid: Binding(
                    get: { self.nodeAddressValid },
                    set: { self.nodeAddressValid = $0 }
                )
            )

            StyledFloatingPointField(
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
}
