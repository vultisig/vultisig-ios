////
////  TransactionMemoWithdrawPool.swift
////  VultisigApp
////
////  Created by Enrique Souza Soares on 12/08/24.
////

import SwiftUI
import Foundation
import Combine

class TransactionMemoWithdrawPool: TransactionMemoAddressable, ObservableObject {
    @Published var basisPoint: Int64 = .zero
    @Published var affiliate: String
    @Published var fee: Int64

    // Internal
    @Published var basisPointValid: Bool = false
    @Published var affiliateValid: Bool = true
    @Published var feeValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init(affiliate: String = "vi", fee: Int64 = 50) {
        self.affiliate = affiliate
        self.fee = fee
        setupValidation()
    }
    
    private func setupValidation() {
        Publishers.CombineLatest3($basisPointValid, $affiliateValid, $feeValid)
            .map { $0 && $1 && $2 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        toString()
    }
    
    func toString() -> String {
        var memo = "POOL-:\(self.basisPoint)"
        if !self.affiliate.isEmpty {
            memo += ":\(self.affiliate)"
        }
        if self.fee != .zero {
            memo += self.affiliate.isEmpty ? "::\(self.fee)" : ":\(self.fee)"
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("basisPoint", self.basisPoint.description)
        dict.set("affiliate", self.affiliate)
        dict.set("fee", "\(self.fee)")
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            
            StyledFloatingPointField(
                placeholder: "Percentage",
                value: Binding(
                    get: { Double(self.basisPoint) },
                    set: { self.basisPoint = Int64($0) }
                ),
                format: .number,
                isValid: Binding(
                    get: { self.basisPointValid },
                    set: { self.basisPointValid = $0 }
                )
            )
        })
    }
}
