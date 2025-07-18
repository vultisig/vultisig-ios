//
//  FunctionCallTronUnfreeze.swift
//  VultisigApp
//
//  Created on 02/01/25.
//

import SwiftUI
import Foundation
import Combine
import VultisigCommonData

struct FunctionCallTronUnfreezeView: View {
    @ObservedObject var unfreezeModel: FunctionCallTronUnfreeze

    var body: some View {
        VStack(spacing: 16) {
            // Resource type selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Resource Type")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Resource", selection: $unfreezeModel.resource) {
                    ForEach(TronResourceType.allCases) { type in
                        Text(type.display).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Staked balance display
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Staked Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(unfreezeModel.maxUnfreezeAmount.formatForDisplay()) TRX")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Amount field
            StyledFloatingPointField(
                placeholder: Binding(
                    get: {
                        "Amount to unfreeze (Max: \(unfreezeModel.maxUnfreezeAmount.formatForDisplay()) TRX)"
                    },
                    set: { _ in }
                ),
                value: $unfreezeModel.amount,
                isValid: .constant(true)
            )

            // Max button
            HStack {
                Spacer()
                Button(action: {
                    unfreezeModel.amount = unfreezeModel.maxUnfreezeAmount
                }) {
                    Text("MAX")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                .disabled(unfreezeModel.maxUnfreezeAmount <= 0)
            }

            // Show appropriate message based on staked balance
            if unfreezeModel.maxUnfreezeAmount == 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)

                    Text("You don't have any TRX staked for \(unfreezeModel.resource.rawValue.lowercased()). Try freezing TRX first.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 8)
            } else {
                // Warning about 14-day waiting period
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text("After unfreezing, you must wait 14 days before withdrawing your TRX")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 8)
            }
        }
    }
}


class FunctionCallTronUnfreeze: FunctionCallAddressable, ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var resource: TronResourceType = .energy
    @Published var maxUnfreezeAmount: Decimal = 0.0
    @Published var isTheFormValid: Bool = false

    private let energyStaked: Int64
    private let bandwidthStaked: Int64
    private var cancellables = Set<AnyCancellable>()

    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    init(
        tx: SendTransaction,
        functionCallViewModel: FunctionCallViewModel,
        energyStaked: Int64,
        bandwidthStaked: Int64
    ) {
        self.energyStaked = energyStaked
        self.bandwidthStaked = bandwidthStaked
        
        self.updateMaxUnfreezeAmount()
        self.amount = self.maxUnfreezeAmount

        $resource
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateMaxUnfreezeAmount()
                self?.amount = self?.maxUnfreezeAmount ?? 0
            }
            .store(in: &cancellables)
            
        Publishers.CombineLatest($amount, $maxUnfreezeAmount)
            .map { amount, maxAmount in
                return amount > 0 && amount <= maxAmount
            }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }

    private func updateMaxUnfreezeAmount() {
        let sunAmount = (resource == .energy) ? energyStaked : bandwidthStaked
        self.maxUnfreezeAmount = Decimal(sunAmount) / Decimal(1_000_000)
    }
    
    func toString() -> String {
        let amountInSun = NSDecimalNumber(decimal: amount * Decimal(1_000_000)).intValue
        return "UNFREEZE:\(resource.rawValue):\(amountInSun)"
    }
    
    var description: String {
        return toString()
    }
    
    var toAddress: String? {
        return nil
    }
    
    func getTransactionType() -> VSTransactionType {
        return .unspecified
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("amount", "\(amount)")
        dict.set("resource", resource.rawValue)
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        return AnyView(FunctionCallTronUnfreezeView(unfreezeModel: self))
    }
} 