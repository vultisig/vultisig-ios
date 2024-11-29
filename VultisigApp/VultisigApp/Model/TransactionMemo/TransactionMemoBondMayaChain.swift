//
//  TransactionMemoBond.swift
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

class TransactionMemoBondMayaChain: TransactionMemoAddressable, ObservableObject
{
    @Published var amount: Double = 1
    @Published var nodeAddress: String = ""
    @Published var fee: Int64 = .zero

    // Internal
    @Published var nodeAddressValid: Bool = false
    @Published var feeValid: Bool = true

    @Published var selectedAsset: IdentifiableString = .init(value: "Asset")

    @Published var assets: [IdentifiableString] = []

    @Published var isTheFormValid: Bool = false

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
        setupValidation()

        if assets != nil {
            self.assets = assets ?? []
        } else {

            DispatchQueue.main.async {
                MayachainService.shared.getDepositAssets {
                    [weak self] assetsResponse in
                    self?.assets = assetsResponse.map {
                        IdentifiableString(value: $0)
                    }
                }
            }
        }
    }

    private func setupValidation() {
        Publishers.CombineLatest($nodeAddressValid, $feeValid)
            .map { $0 && $1 }
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
                    descriptionProvider: { $0.value },
                    onSelect: { asset in
                        self.selectedAsset = asset
                    }
                )

                StyledIntegerField(
                    placeholder: "LPUNITS",
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
