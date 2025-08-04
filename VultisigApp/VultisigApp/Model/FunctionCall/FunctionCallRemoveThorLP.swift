//
//  FunctionCallRemoveThorLP.swift
//  VultisigApp
//

import SwiftUI
import Foundation
import Combine
import BigInt

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
        
        // Set transaction amount to THORChain native fee (0.02 RUNE)
        // This is the minimum dust amount to initiate withdrawal on THORChain
        self.tx.amount = "0.02"
        
        setupValidation()
        
        // Automatically get the THORChain address to load positions
        if let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
            loadPositions(runeAddress: thorCoin.address)
        } else {
            // No THORChain address found
            self.isLoading = false
            self.errorMessage = "No THORChain address found in vault. You need a RUNE address to manage LP positions."
        }
    }
    
    // Clean pool name functionality moved to THORChainUtils
    
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
    
    private func loadPositions(runeAddress: String) {
        Task {
            do {
                print("FunctionCallRemoveThorLP: Loading positions for RUNE address: \(runeAddress)")
                
                let positions = try await ThorchainService.shared.fetchLPPositions(runeAddress: runeAddress)
                
                DispatchQueue.main.async {
                    self.lpPositions = positions
                    self.isLoading = false
                    if positions.isEmpty {
                        self.errorMessage = "No THORChain LP positions found. You need to add liquidity first."
                    } else if positions.count == 1 {
                        // Auto-select if only one position
                        self.selectedPosition = positions.first
                        self.positionValid = true
                    }
                }
            } catch {
                print("FunctionCallRemoveThorLP: Error loading LP positions: \(error)")
                print("FunctionCallRemoveThorLP: Error details: \(error.localizedDescription)")
                DispatchQueue.main.async {
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
            dict.set("dustAmount", "0.02 RUNE")
        }
        dict.set("memo", toString())
        return dict
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.formatToDecimal(digits: 8)
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    var transactionAmountInfo: String {
        return "Sending: 0.02 RUNE (THORChain native fee to initiate withdrawal)"
    }
    
    var dustAmount: Decimal {
        return Decimal(string: "0.02") ?? 0.02
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
                
                // Transaction info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transaction Details")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chain: THORChain")
                                .font(.caption)
                                .foregroundColor(.neutral0)
                            Text(model.transactionAmountInfo)
                                .font(.caption)
                                .foregroundColor(.turquoise600)
                                .fontWeight(.semibold)
                            Text("Withdrawal initiated on THORChain")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.blue600.opacity(0.1))
                    .cornerRadius(8)
                    
                    Text("LP withdrawals are always initiated on THORChain using RUNE. Ensure your LP position value exceeds the outbound fees for successful withdrawal.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
                            Text(ThorchainService.cleanPoolName(position.asset))
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
    
    // Clean pool name functionality moved to THORChainUtils
    
    private func formatDepositValue(_ value: String) -> String {
        // Convert from base units (1e8) to display format
        if let decimal = Decimal(string: value) {
            let displayValue = decimal / 100_000_000 // Convert from 1e8
            return displayValue.formatToDecimal(digits: 8)
        }
        return value
    }
    
    private func getAssetTicker(from poolName: String) -> String {
        // Extract asset ticker from pool name (e.g., "ETH.USDC" -> "USDC")
        let cleanName = ThorchainService.cleanPoolName(poolName)
        let components = cleanName.split(separator: ".")
        if components.count >= 2 {
            return String(components[1])
        }
        return "Asset"
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ThorchainService.cleanPoolName(position.asset))
                        .font(.body16MenloBold)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LP Units")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(position.poolUnits)
                                .font(.caption)
                                .foregroundColor(.neutral0)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RUNE Deposited")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatDepositValue(position.runeDepositValue))
                                .font(.caption)
                                .foregroundColor(.neutral0)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(getAssetTicker(from: position.asset)) Deposited")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatDepositValue(position.assetDepositValue))
                                .font(.caption)
                                .foregroundColor(.neutral0)
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.turquoise600)
                }
            }
            .padding()
            .background(isSelected ? Color.blue600.opacity(0.3) : Color.blue600.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
