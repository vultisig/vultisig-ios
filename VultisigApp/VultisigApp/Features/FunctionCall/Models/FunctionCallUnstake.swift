//
//  FunctionCallUnstake.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/10/24.
//

import SwiftUI
import Foundation
import Combine

class FunctionCallUnstake: FunctionCallAddressable, ObservableObject {
    @Published var amount: Decimal = 1
    @Published var nodeAddress: String = ""

    // Internal
    @Published var amountValid: Bool = true
    @Published var nodeAddressValid: Bool = false
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

    required init() {
    }

    func initialize() {
        setupValidation()
    }

    private func setupValidation() {
        Publishers.CombineLatest($amountValid, $nodeAddressValid)
            .map { $0 && $1 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        return "w"
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

            StyledFloatingPointField(
                label: NSLocalizedString("amount", comment: ""),
                placeholder: NSLocalizedString("enterAmount", comment: ""),
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                ))
        }.onAppear {
            self.initialize()
        })
    }
}
