//
//  FunctionCallRemoveLiquidityMaya.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import Combine
import Foundation
import SwiftUI

class FunctionCallRemoveLiquidityMaya: ObservableObject
{
    @Published var fee: Int64 = .zero
    
    // Internal
    @Published var feeValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    required init() {
        setupValidation()
    }
    
    private func setupValidation() {
        $feeValid
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        let memo =
        "POOL-:\(self.fee)"
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("BPS", "\(self.fee)")
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(
            VStack {
                
                StyledIntegerField(
                    placeholder: NSLocalizedString("bps", comment: ""),
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
            })
    }
}
