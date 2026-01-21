//
//  FunctionCallBond.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import Combine
import Foundation
import SwiftUI

struct IdentifiableString: Identifiable, Equatable {
    let id = UUID()
    let value: String
}

class FunctionCallBondMayaChain: FunctionCallAddressable, ObservableObject
{
    @Published var amount: Decimal = 1
    @Published var nodeAddress: String = ""
    @Published var fee: Int64 = .zero
    
    // Internal
    @Published var nodeAddressValid: Bool = false
    @Published var feeValid: Bool = true
    @Published var assetValid: Bool = false
    
    @Published var selectedAsset: IdentifiableString = .init(value: NSLocalizedString("assetLabel", comment: ""))
    
    @Published var assets: [IdentifiableString] = []
    
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    
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
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(assets: [IdentifiableString]?) {
        if assets != nil {
            self.assets = assets ?? []
        }
    }
    
    func initialize() {
        setupValidation()
        
        if assets.isEmpty {
            DispatchQueue.main.async {
                MayachainService.shared.getDepositAssets {[weak self] assetsResponse in
                    self?.assets = assetsResponse.map {
                        IdentifiableString(value: $0)
                    }
                }
            }
        }
    }
    
    private func setupValidation() {
        Publishers.CombineLatest3($nodeAddressValid, $feeValid, $assetValid)
            .map { $0 && $1 && $2  }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        let memo =
        "BOND:\(self.selectedAsset.value):\(self.fee):\(self.nodeAddress)"
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("asset", self.selectedAsset.value)
        dict.set("LPUNITS", "\(self.fee)")
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(
            VStack {
                
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
                        self.assetValid = asset.value.lowercased() != NSLocalizedString("assetLabel", comment: "").lowercased()
                    }
                )
                
                StyledIntegerField(
                    placeholder: NSLocalizedString("lpUnitsLabel", comment: ""),
                    value: Binding(
                        get: { self.fee },
                        set: { self.fee = $0 }
                    ),
                    format: .number,
                    isValid: Binding(
                        get: { self.feeValid },
                        set: { self.feeValid = $0 }
                    )
                )
                
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
