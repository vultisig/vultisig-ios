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
    
    func findBondByIdentifier(_ identifier: String) -> ThorchainActiveNodeBondResponse? {
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
        AnyView(UnbondView(viewModel: self))
    }
}

struct UnbondView: View {
    @ObservedObject var viewModel: FunctionCallUnbond
    @State private var amountText: String = "0"
    
    var body: some View {
        VStack {
            
            if viewModel.assets.count > 0 {
                
                GenericSelectorDropDown(
                    items: Binding.constant(viewModel.assets),
                    selected: Binding(
                        get: { viewModel.selectedAsset },
                        set: { viewModel.selectedAsset = $0 }
                    ),
                    mandatoryMessage: "*",
                    descriptionProvider: { $0.value },
                    onSelect: { asset in
                        viewModel.selectedAsset = asset
                        viewModel.assetValid = asset.value.lowercased() != "Node".lowercased()
                        
                        if let bond = viewModel.findBondByIdentifier(asset.value) {
                            viewModel.amount = bond.bondAmount
                            viewModel.nodeAddress = bond.nodeAddress
                            
                            self.amountText = bond.bondAmount.formatDecimalToLocale()
                            
                            viewModel.lastUpdateTime = Date()
                            viewModel.objectWillChange.send()
                        }
                    }
                )
                
            }
            
            FunctionCallAddressTextField(
                memo: viewModel,
                addressKey: "nodeAddress",
                isAddressValid: .init(
                    get: { viewModel.nodeAddressValid },
                    set: { viewModel.nodeAddressValid = $0 }
                )
            )
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Amount\(viewModel.amountValid ? "" : " *")")
                        .font(.body14MontserratMedium)
                        .foregroundColor(.neutral0)
                    if !viewModel.amountValid {
                        Text("*")
                            .font(.body8Menlo)
                            .foregroundColor(.red)
                    }
                }
                
                TextField("", text: $amountText)
                    .id("amount-field-\(viewModel.lastUpdateTime.timeIntervalSince1970)")
                    .placeholder(when: amountText.isEmpty) {
                        Text("Amount".capitalized)
                            .foregroundColor(.gray)
                    }
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
                    .submitLabel(.done)
                    .padding(12)
                    .background(Color.blue600)
                    .cornerRadius(12)
                    .onChange(of: amountText) { _, newValue in
                        viewModel.amount = newValue.toDecimal()
                    }
            }
            
            FunctionCallAddressTextField(
                memo: viewModel,
                addressKey: "provider",
                isOptional: true,
                isAddressValid: .init(
                    get: { viewModel.providerValid },
                    set: { viewModel.providerValid = $0 }
                )
            )
        }
        .onAppear {
            amountText = viewModel.amount.formatDecimalToLocale()
        }
    }
}
