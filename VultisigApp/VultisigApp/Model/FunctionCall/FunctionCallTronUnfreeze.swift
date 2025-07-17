//
//  FunctionCallTronUnfreeze.swift
//  VultisigApp
//
//  Created on 02/01/25.
//

import SwiftUI
import Foundation
import Combine

class FunctionCallTronUnfreeze: FunctionCallAddressable, ObservableObject {
    @Published var resource: TronResourceType = .energy
    @Published var receiver: String = "" // Optional: if resources were delegated
    
    // Internal validation
    @Published var resourceValid: Bool = true
    @Published var receiverValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    
    private var tx: SendTransaction
    
    var addressFields: [String: String] {
        get {
            var fields: [String: String] = [:]
            if !receiver.isEmpty {
                fields["receiver"] = receiver
            }
            return fields
        }
        set {
            if let value = newValue["receiver"] {
                receiver = value
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, functionCallViewModel: FunctionCallViewModel
    ) {
        self.tx = tx
        setupValidation()
    }
    
    private func setupValidation() {
        // Validate receiver address if provided
        $receiver
            .map { address in
                if address.isEmpty {
                    return true
                }
                // Basic TRON address validation (starts with T and is 34 characters)
                return address.hasPrefix("T") && address.count == 34
            }
            .assign(to: \.receiverValid, on: self)
            .store(in: &cancellables)
        
        // Combine all validations
        Publishers.CombineLatest($resourceValid, $receiverValid)
            .map { $0 && $1 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "UNFREEZE:\(resource.rawValue)"
        if !receiver.isEmpty {
            memo += ":\(receiver)"
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("resource", resource.rawValue)
        if !receiver.isEmpty {
            dict.set("receiver", receiver)
        }
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack(spacing: 16) {
            // Resource type selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Resource Type to Unfreeze")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Resource", selection: Binding<TronResourceType>(
                    get: { self.resource },
                    set: { self.resource = $0 }
                )) {
                    ForEach(TronResourceType.allCases) { type in
                        Text(type.display).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Receiver field (optional)
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "receiver",
                isOptional: true,
                isAddressValid: Binding(
                    get: { self.receiverValid },
                    set: { self.receiverValid = $0 }
                ),
                chain: tx.coin.chain
            )
            .padding(.top, 8)
            
            // Info text
            VStack(alignment: .leading, spacing: 4) {
                Text("ℹ️ Important:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• TRX can only be unfrozen after the freeze duration expires")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("• Minimum freeze duration is 3 days")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("• After unfreezing, resources (Energy/Bandwidth) will be removed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        })
    }
} 