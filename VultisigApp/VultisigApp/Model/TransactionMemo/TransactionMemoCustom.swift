//
//  TransactionMemoCustom.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoCustom: TransactionMemoAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = false
    
    @Published var amount: Double = 0.0
    @Published var custom: String = ""
    
    // Internal
    @Published var amountValid: Bool = false
    @Published var customValid: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {
        setupValidation()
    }
    
    init(custom: String) {
        self.custom = custom
        setupValidation()
    }
    
    private func setupValidation() {
        Publishers.CombineLatest($amountValid, $customValid)
            .map { $0 && $1 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return self.custom
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
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
            StyledTextField(
                placeholder: "Custom Memo",
                text: Binding(
                    get: { self.custom },
                    set: { self.custom = $0 }
                ),
                isValid: Binding(
                    get: { self.customValid },
                    set: { self.customValid = $0 }
                )
            )
        })
    }
}
