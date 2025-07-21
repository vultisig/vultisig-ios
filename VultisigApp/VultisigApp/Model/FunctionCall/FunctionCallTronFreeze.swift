//
//  FunctionCallTronFreeze.swift
//  VultisigApp
//
//  Created on 02/01/25.
//

import SwiftUI
import Foundation
import Combine

enum TronResourceType: String, CaseIterable, Identifiable {
    case bandwidth = "BANDWIDTH"
    case energy = "ENERGY"
    
    var id: String { self.rawValue }
    
    var display: String {
        switch self {
        case .bandwidth:
            return "Bandwidth"
        case .energy:
            return "Energy"
        }
    }
}

class FunctionCallTronFreeze: FunctionCallAddressable, ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var resource: TronResourceType = .energy
    @Published var receiver: String = "" // Optional: delegate resource to another address
    
    // Internal validation
    @Published var amountValid: Bool = false
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
        
        // Auto-fill amount with available balance
        self.amount = tx.coin.balanceDecimal
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    var estimatedResources: String {
        if amount <= 0 {
            return "0"
        }
        
        // Convert TRX to SUN for calculation
        let amountInSun = amount * Decimal(1_000_000)
        
        if resource == .energy {
            // Rough estimate: 1 TRX = ~30 Energy per day
            let energy = (amountInSun / Decimal(1_000_000)) * 30
            return "\(Int(truncating: NSDecimalNumber(decimal: energy))) Energy/day"
        } else {
            // Rough estimate: 1 TRX = ~200 Bandwidth per day
            let bandwidth = (amountInSun / Decimal(1_000_000)) * 200
            return "\(Int(truncating: NSDecimalNumber(decimal: bandwidth))) Bandwidth/day"
        }
    }
    
    private func setupValidation() {
        // Validate amount is greater than 0
        $amount
            .map { $0 > 0 && $0 <= self.tx.coin.balanceDecimal }
            .assign(to: \.amountValid, on: self)
            .store(in: &cancellables)
        
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
        Publishers.CombineLatest3($amountValid, $resourceValid, $receiverValid)
            .map { $0 && $1 && $2 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        // Convert TRX amount to SUN (1 TRX = 1,000,000 SUN)
        let amountInSun = NSDecimalNumber(decimal: amount * Decimal(1_000_000)).intValue
        var memo = "FREEZE:\(resource.rawValue):\(amountInSun)"
        // Note: Duration is no longer used in FreezeBalanceV2, resources last until unfrozen
        if !receiver.isEmpty {
            memo += ":\(receiver)"
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("amount", "\(amount)")
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
                Text("Resource Type")
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
            
            // Available balance display
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Available Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(tx.coin.balanceDecimal.formatForDisplay()) TRX")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: {
                    self.amount = self.tx.coin.balanceDecimal
                }) {
                    Text("MAX")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // Amount field
            StyledFloatingPointField(
                placeholder: Binding(
                    get: { "Amount to freeze" },
                    set: { _ in }
                ),
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = min($0, self.tx.coin.balanceDecimal) }
                ),
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                )
            )
            
            // Note: Duration field removed as FreezeBalanceV2 doesn't use it
            // Resources last until explicitly unfrozen
            
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
            
            // Estimated resources
            if amount > 0 {
                HStack {
                    Text("Estimated Resources:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(estimatedResources)
                        .font(.caption)
                        .foregroundColor(.turquoise600)
                }
                .padding(.top, 4)
            }
            
            // Info text
            VStack(alignment: .leading, spacing: 8) {
                Text("Freezing TRX reduces transaction fees")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if resource == .energy {
                    Text("• Recommended: 8,000+ TRX for USDT transfers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• Each TRC20 transfer uses ~65,000 Energy")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("• Bandwidth is used for regular TRX transfers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• 1 Bandwidth = 1 byte of transaction")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text("• Resources last until you unfreeze")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        })
    }
} 
