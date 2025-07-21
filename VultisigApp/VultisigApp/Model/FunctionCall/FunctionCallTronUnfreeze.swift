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
            // Resource type selector using GenericSelectorDropDown
            VStack(alignment: .leading, spacing: 8) {
                Text("Resource Type")
                    .font(.caption)
                    .foregroundColor(.secondary)

                GenericSelectorDropDown(
                    items: Binding(
                        get: { unfreezeModel.resourceItems },
                        set: { unfreezeModel.resourceItems = $0 }
                    ),
                    selected: Binding(
                        get: { unfreezeModel.selectedResource },
                        set: { unfreezeModel.selectedResource = $0 }
                    ),
                    mandatoryMessage: nil,
                    descriptionProvider: { $0.value },
                    onSelect: { selected in
                        unfreezeModel.selectResource(selected)
                    }
                )
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
        .onAppear {
            unfreezeModel.updateMaxUnfreezeAmount()
            unfreezeModel.amount = unfreezeModel.maxUnfreezeAmount
        }
    }
}


class FunctionCallTronUnfreeze: FunctionCallAddressable, ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var maxUnfreezeAmount: Decimal = 0.0
    @Published var isTheFormValid: Bool = false
    
    @Published var selectedResource: IdentifiableString = .init(value: "Bandwidth (for regular transactions)")
    @Published var resourceItems: [IdentifiableString] = [
        .init(value: "Bandwidth (for regular transactions)"),
        .init(value: "Energy (for smart contracts)")
    ]

    private let energyStaked: Int64
    private let bandwidthStaked: Int64
    private var cancellables = Set<AnyCancellable>()
    
    // Keep internal resource type for logic
    var resource: TronResourceType = .bandwidth

    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    init(
        tx: SendTransaction,
        functionCallViewModel: FunctionCallViewModel,
        energyStaked: Int64,
        bandwidthStaked: Int64,
        initialResource: TronResourceType = .bandwidth // <-- Default to bandwidth
    ) {
        self.energyStaked = energyStaked
        self.bandwidthStaked = bandwidthStaked
        self.resource = initialResource
        
        // Set initial selected resource based on initialResource
        if initialResource == .energy {
            self.selectedResource = .init(value: "Energy (for smart contracts)")
        }
        
        print("ENERGY STAKED \(energyStaked)")
        print("BANDWIDTH STAKED \(bandwidthStaked)")
        print("RESOURCE \(initialResource)")

        self.updateMaxUnfreezeAmount()
        self.amount = self.maxUnfreezeAmount
            
        Publishers.CombineLatest($amount, $maxUnfreezeAmount)
            .map { amount, maxAmount in
                return amount > 0 && amount <= maxAmount
            }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    func selectResource(_ selected: IdentifiableString) {
        self.selectedResource = selected
        
        // Update internal resource type based on selection
        if selected.value.lowercased().contains("energy") {
            self.resource = .energy
        } else {
            self.resource = .bandwidth
        }
        
        print("Resource changed to: \(self.resource)")
        self.updateMaxUnfreezeAmount()
        self.amount = self.maxUnfreezeAmount
        self.objectWillChange.send()
    }

    func updateMaxUnfreezeAmount() {
        let sunAmount = (resource == .energy) ? energyStaked : bandwidthStaked
        print("Updating maxUnfreezeAmount for \(resource): staked=\(sunAmount), energyStaked=\(energyStaked), bandwidthStaked=\(bandwidthStaked)")
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
