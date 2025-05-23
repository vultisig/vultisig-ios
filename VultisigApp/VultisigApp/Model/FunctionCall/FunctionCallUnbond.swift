//
//  FunctionCallUnbond.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

class FunctionCallUnbond: FunctionCallAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = false
    
    @Published var lastUpdateTime: Date = Date()
    
    @Published var nodeAddress: String = ""
    @Published var amount: Decimal = 0.0
    @Published var provider: String = ""
    
    // Internal
    @Published var nodeAddressValid: Bool = false
    @Published var amountValid: Bool = true // if ZERO it will unbond all.
    @Published var providerValid: Bool = true
    
    @Published var selectedAsset: IdentifiableString = .init(value: "Node")
    @Published var assetValid: Bool = false
    @Published var assets: [IdentifiableString] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private var bonds: [ThorchainActiveNodeBondResponse]?
    
    var addressFields: [String: String] {
        get {
            var fields = ["nodeAddress": nodeAddress]
            if !provider.isEmpty {
                fields["provider"] = provider
            }
            return fields
        }
        set {
            if let value = newValue["nodeAddress"] {
                nodeAddress = value
            }
            if let value = newValue["provider"] {
                provider = value
            }
        }
    }
    
    required init(bonds: [ThorchainActiveNodeBondResponse]?) {
        self.bonds = bonds
        formatBonds(bonds)
        setupValidation()
    }
    
    init(nodeAddress: String, amount: Decimal = 0.0, provider: String = "") {
        self.nodeAddress = nodeAddress
        self.amount = amount
        self.provider = provider
        setupValidation()
    }
    
    private func formatBonds(_ bonds: [ThorchainActiveNodeBondResponse]?) {
        var i = 0
        for bond in bonds ?? [] {
            let addr = bond.nodeAddress
            let prefix = String(addr.prefix(6))
            let suffix = String(addr.suffix(4))
            let shortenedAddress = "\(prefix)...\(suffix)"
            
            let display = "\(i)\t\(shortenedAddress)\t\(bond.bondAmount.formatDecimalToLocale())"
            assets.append(IdentifiableString(value: display))
            i += 1
        }
    }
    
    private func findBondByIdentifier(_ identifier: String) -> ThorchainActiveNodeBondResponse? {
        guard let bonds = bonds else { return nil }
        let index = Int(identifier.split(separator: "\t")[0]) ?? 0
        return bonds[index]
    }
    
    private func setupValidation() {
        Publishers.CombineLatest3($nodeAddressValid, $amountValid, $providerValid)
            .map { $0 && $1 && $2 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    var amountInUnits: String {
        let amountInSats = self.amount * pow(10, 8)
        return amountInSats.description
    }
    
    func toString() -> String {
        var memo = "UNBOND:\(self.nodeAddress):\(amountInUnits)"
        if !self.provider.isEmpty {
            memo += ":\(self.provider)"
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("Unbond amount", "\(self.amount)")
        dict.set("provider", self.provider)
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
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    self.selectedAsset = asset
                    self.assetValid = asset.value.lowercased() != "Node".lowercased()
                    
                    if let bond = self.findBondByIdentifier(asset.value) {
                        withAnimation {
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                
                                self.amount = bond.bondAmount
                                self.nodeAddress = bond.nodeAddress
                                self.lastUpdateTime = Date() // ⬅️ Isto força a view a atualizar
                                self.objectWillChange.send()
                            }
                        }
                    }
                }
            )

            FunctionCallAddressTextField(
                memo: self,
                addressKey: "nodeAddress",
                isAddressValid: Binding(
                    get: { self.nodeAddressValid },
                    set: { self.nodeAddressValid = $0 }
                )
            )

            StyledFloatingPointField(
                placeholder: Binding(
                    get: { "Amount" },
                    set: { _ in }
                ),
                value: Binding(
                    get: { self.amount },
                    set: {
                        self.amount = $0
                        DispatchQueue.main.async {
                            self.lastUpdateTime = Date()
                            self.objectWillChange.send()
                        }
                    }
                ),
                isValid: Binding(
                    get: { true },
                    set: { _ in }
                )
            )
            .id("field-\(nodeAddress)-\(amount.formatDecimalToLocale())") // ✅ Força atualização confiável

            FunctionCallAddressTextField(
                memo: self,
                addressKey: "provider",
                isOptional: true,
                isAddressValid: Binding(
                    get: { self.providerValid },
                    set: { self.providerValid = $0 }
                )
            )
        })
    }
}
