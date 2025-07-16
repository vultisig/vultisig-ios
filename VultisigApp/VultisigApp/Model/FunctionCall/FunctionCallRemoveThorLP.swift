//
//  FunctionCallRemoveThorLP.swift
//  VultisigApp
//

import SwiftUI
import Foundation
import Combine

class FunctionCallRemoveThorLP: FunctionCallAddressable, ObservableObject {
    @Published var selectedPosition: ThorchainLPPosition?
    @Published var withdrawPercentage: Decimal = 50.0 // Default to 50%
    
    // Internal validation
    @Published var positionValid: Bool = false
    @Published var percentageValid: Bool = true
    @Published var isTheFormValid: Bool = false
    
    // Available positions
    @Published var lpPositions: [ThorchainLPPosition] = []
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    
    var tx: SendTransaction
    private var functionCallViewModel: FunctionCallViewModel
    private var vault: Vault
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault) {
        self.tx = tx
        self.functionCallViewModel = functionCallViewModel
        self.vault = vault
        setupValidation()
        loadPositions()
    }
    
    func cleanPoolName(_ asset: String) -> String {
        // Remove contract addresses from pool names
        if let dashIndex = asset.firstIndex(of: "-"),
           let hexPrefix = asset[asset.index(after: dashIndex)...].firstIndex(of: "0"),
           asset[hexPrefix...].starts(with: "0X") {
            return String(asset[..<dashIndex])
        }
        return asset
    }
    
    private func setupValidation() {
        Publishers.CombineLatest($positionValid, $percentageValid)
            .map { $0 && $1 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
        
        // Validate percentage is between 1 and 100
        $withdrawPercentage
            .map { percentage in
                percentage >= 1 && percentage <= 100
            }
            .assign(to: \.percentageValid, on: self)
            .store(in: &cancellables)
    }
    
    private func loadPositions() {
        Task {
            do {
                print("FunctionCallRemoveThorLP: Loading positions for address: \(tx.coin.address)")
                
                let positions = try await ThorchainService.shared.fetchLPPositions(runeAddress: tx.coin.address)
                print("FunctionCallRemoveThorLP: Found \(positions.count) positions")
                
                await MainActor.run {
                    self.lpPositions = positions
                    self.isLoading = false
                    if positions.isEmpty {
                        self.errorMessage = "No THORChain LP positions found. You need to add liquidity first."
                    } else if positions.count == 1 {
                        self.selectedPosition = positions.first
                        self.positionValid = true
                    }
                }
            } catch {
                print("FunctionCallRemoveThorLP: Error loading LP positions: \(error)")
                print("FunctionCallRemoveThorLP: Error details: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Failed to load LP positions: \(error.localizedDescription)"
                }
            }
        }
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        guard let position = selectedPosition else {
            return ""
        }
        
        // Convert percentage to basis points (10000 = 100%)
        let basisPoints = NSDecimalNumber(decimal: withdrawPercentage * 100).intValue
        
        let lpData = RemoveLPMemoData(
            pool: position.asset,
            basisPoints: basisPoints
        )
        return lpData.memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        if let position = selectedPosition {
            dict.set("pool", position.asset)
            dict.set("withdrawPercentage", "\(withdrawPercentage)%")
            dict.set("units", position.poolUnits)
        }
        dict.set("memo", toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallRemoveThorLPView(model: self))
    }
}

struct FunctionCallRemoveThorLPView: View {
    @ObservedObject var model: FunctionCallRemoveThorLP
    
    var body: some View {
        VStack(spacing: 16) {
            
            if model.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            } else if let errorMessage = model.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if model.lpPositions.isEmpty {
                Text("No LP positions found")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Position selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select LP Position")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(model.lpPositions, id: \.asset) { position in
                        PositionRowView(
                            position: position,
                            isSelected: model.selectedPosition?.asset == position.asset,
                            onTap: {
                                model.selectedPosition = position
                                model.positionValid = true
                            }
                        )
                    }
                }
                .padding(.horizontal)
                
                // Percentage slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Withdraw Percentage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(NSDecimalNumber(decimal: model.withdrawPercentage).intValue)%")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(truncating: NSDecimalNumber(decimal: model.withdrawPercentage)) },
                            set: { model.withdrawPercentage = Decimal($0) }
                        ),
                        in: 1...100,
                        step: 1
                    )
                    .accentColor(.blue)
                    
                    HStack {
                        Text("1%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("100%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                
                // Show withdrawal details if position selected
                if let position = model.selectedPosition {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Withdrawal Details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Pool:")
                            Text(model.cleanPoolName(position.asset))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        HStack {
                            Text("Your LP Units:")
                            Text(position.poolUnits)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
            }
        }
    }
}

// Helper view for position row
private struct PositionRowView: View {
    let position: ThorchainLPPosition
    let isSelected: Bool
    let onTap: () -> Void
    
    private func cleanPoolName(_ asset: String) -> String {
        // Remove contract addresses from pool names
        if let dashIndex = asset.firstIndex(of: "-"),
           let hexPrefix = asset[asset.index(after: dashIndex)...].firstIndex(of: "0"),
           asset[hexPrefix...].starts(with: "0X") {
            return String(asset[..<dashIndex])
        }
        return asset
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cleanPoolName(position.asset))
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text("Units: \(position.poolUnits)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
} 