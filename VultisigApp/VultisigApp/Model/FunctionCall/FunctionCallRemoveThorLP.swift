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
    @Published var withdrawPercentage: Decimal = 100.0
    @Published var positionValid: Bool = false
    @Published var percentageValid: Bool = true
    @Published var isTheFormValid: Bool = false
    @Published var lpPositions: [ThorchainLPPosition] = []
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var customErrorMessage: String? = nil
    
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
        self.tx.amount = "0.02"
        
    }
    
    func initialize() {
        setupValidation()
        
        if let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
            loadPositions(runeAddress: thorCoin.address)
        } else {
            self.isLoading = false
            self.errorMessage = "No THORChain address found in vault. You need a RUNE address to manage LP positions."
        }
    }
    
    private func setupValidation() {
        Publishers.CombineLatest($positionValid, $percentageValid)
            .map { $0 && $1 }
            .assign(to: \..isTheFormValid, on: self)
            .store(in: &cancellables)
        
        $withdrawPercentage
            .map { $0 >= 1 && $0 <= 100 }
            .assign(to: \..percentageValid, on: self)
            .store(in: &cancellables)
    }
    
    private func loadPositions(runeAddress: String) {
        Task {
            do {
                let positions = try await ThorchainService.shared.fetchLPPositions(runeAddress: runeAddress)
                DispatchQueue.main.async {
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
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Failed to load LP positions: \(error.localizedDescription)"
                }
            }
        }
    }
    
    var description: String {
        toString()
    }
    
    func toString() -> String {
        guard let position = selectedPosition else { return "" }
        let basisPoints = NSDecimalNumber(decimal: withdrawPercentage * 100).intValue
        let lpData = RemoveLPMemoData(pool: position.asset, basisPoints: basisPoints)
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
        "Sending: 0.02 RUNE (THORChain native fee to initiate withdrawal)"
    }
    
    var dustAmount: Decimal {
        Decimal(string: "0.02") ?? 0.02
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallRemoveThorLPView(model: self).onAppear{
            self.initialize()
        })
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select LP Position")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(model.lpPositions, id: \..asset) { position in
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
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transaction Details")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chain: THORChain")
                                .font(.caption)
                                .foregroundColor(Theme.colors.textPrimary)
                            Text(model.transactionAmountInfo)
                                .font(.caption)
                                .foregroundColor(Theme.colors.primaryAccent1)
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
                    .background(Theme.colors.bgSecondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    Text("LP withdrawals are always initiated on THORChain using RUNE. Ensure your LP position value exceeds the outbound fees for successful withdrawal.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
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

private struct PositionRowView: View {
    let position: ThorchainLPPosition
    let isSelected: Bool
    let onTap: () -> Void
    
    
    
    private func getAssetTicker(from poolName: String) -> String {
        let cleanName = ThorchainService.cleanPoolName(poolName)
        let components = cleanName.split(separator: ".")
        return components.count >= 2 ? String(components[1]) : "Asset"
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ThorchainService.cleanPoolName(position.asset))
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundColor(Theme.colors.textPrimary)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LP Units")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(position.poolUnits)
                                .font(.caption)
                                .foregroundColor(Theme.colors.textPrimary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RUNE Deposited")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text((position.runeDepositValue.toDecimal() / 100_000_000).formatToDecimal(digits: 8))
                                .font(.caption)
                                .foregroundColor(Theme.colors.textPrimary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(getAssetTicker(from: position.asset)) Deposited")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text((position.assetDepositValue.toDecimal() / 100_000_000).formatToDecimal(digits: 8))
                                .font(.caption)
                                .foregroundColor(Theme.colors.textPrimary)
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.colors.primaryAccent1)
                }
            }
            .padding()
            .background(Theme.colors.bgSecondary.opacity( isSelected ? 0.3 : 0.1))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
