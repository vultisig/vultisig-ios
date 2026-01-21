//
//  FunctionCallCosmosUnmerge.swift
//  VultisigApp
//
//  Created on 2025/01/03.
//

import SwiftUI
import Foundation
import Combine

/**
 * THORCHAIN - FUNCTION: "EXECUTE CONTRACT - UNMERGE"
 *
 * UI Elements:
 * • Dropdown: Select token to unmerge
 * • Amount Field: Enter amount of shares to withdraw (displayed as RUJI amount)
 * • Display: Current balance info
 *
 * Action:
 * → Call the RUJI Merge smart contract to withdraw the specified amount
 */

class FunctionCallCosmosUnmerge: ObservableObject {
    @Published var amount: Decimal = 0.0  // User input amount
    @Published var destinationAddress: String = ""
    @Published var fnCall: String = ""
    
    @Published var amountValid: Bool = false
    @Published var fnCallValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    
    @Published var tokens: [IdentifiableString] = []
    @Published var tokenValid: Bool = false
    @Published var selectedToken: IdentifiableString = .init(value: NSLocalizedString("theUnmerge", comment: ""))
    
    @Published var balanceLabel: String = NSLocalizedString("sharesLabel", comment: "")
    @Published var sharePrice: Decimal = 0  // Price per share (not used for transaction)
    @Published var totalShares: String = "0"  // Total shares owned
    @Published var availableBalance: Decimal = 0.0  // Available balance for validation
    @Published var isLoading: Bool = false
    
    @ObservedObject var tx: SendTransaction
    
    private var vault: Vault
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, vault: Vault
    ) {
        self.tx = tx
        self.vault = vault
    }
    
    func initialize() {
        setupValidation()
        loadAvailableTokens()
        preSelectToken()
    }
    
    private func loadAvailableTokens() {
        // Find available merge tokens that have balances
        let availableTokens = ThorchainMergeTokens.tokensToMerge.filter { tokenInfo in
            vault.coins.contains { coin in
                coin.chain == .thorChain &&
                !coin.isNativeToken &&
                coin.ticker.lowercased() == tokenInfo.denom.lowercased().replacingOccurrences(of: "thor.", with: "")
            }
        }
        
        for token in availableTokens {
            tokens.append(.init(value: token.denom.uppercased()))
        }
    }
    
    private func preSelectToken() {
        // Pre-select if we're already on a merged token
        if !tx.coin.isNativeToken,
           let match = ThorchainMergeTokens.tokensToMerge.first(where: {
               $0.denom.lowercased() == "thor.\(tx.coin.ticker.lowercased())"
           }) {
            selectToken(.init(value: match.denom.uppercased()))
        } else if !tokens.isEmpty {
            // If no pre-selection, select the first available token
            selectToken(tokens[0])
        }
    }
    
    func selectToken(_ token: IdentifiableString) {
        selectedToken = token
        tokenValid = true
        destinationAddress = ThorchainMergeTokens.tokensToMerge.first {
            $0.denom.lowercased() == token.value.lowercased()
        }?.wasmContractAddress ?? ""
        tx.toAddress = destinationAddress
        
        if let coin = selectedVaultCoin {
            tx.coin = coin
        }
        
        Task {
            await fetchMergedBalance()
        }
    }
    
    var selectedVaultCoin: Coin? {
        let ticker = selectedToken.value
            .lowercased()
            .replacingOccurrences(of: "thor.", with: "")
        
        return vault.coins.first { coin in
            coin.chain == .thorChain &&
            !coin.isNativeToken &&
            coin.ticker.lowercased() == ticker
        }
    }
    
    @MainActor
    func fetchMergedBalance() async {
        // Prevent multiple concurrent requests
        if isLoading { return }
        
        isLoading = true
        objectWillChange.send() // Force UI update
        defer {
            isLoading = false
            objectWillChange.send() // Force UI update
        }
        
        do {
            let thorAddress = vault.coins.first(where: { $0.chain == .thorChain })?.address ?? ""
            
            guard !thorAddress.isEmpty else {
                print("ERROR: No THORChain address found in vault")
                balanceLabel = NSLocalizedString("noThorAddressFound", comment: "")
                amount = 0
                totalShares = "0"
                sharePrice = 0
                objectWillChange.send()
                return
            }
            
            let rujiBalance = try await ThorchainService.shared.fetchRujiMergeBalance(
                thorAddr: thorAddress,
                tokenSymbol: selectedToken.value
            )
            
            totalShares = rujiBalance.shares
            sharePrice = rujiBalance.price
            
            // Store available balance for validation (shares converted to decimal)
            if let sharesRaw = Decimal(string: rujiBalance.shares) {
                let divisor = NSDecimalNumber(decimal: pow(Decimal(10), 8))
                availableBalance = sharesRaw / divisor.decimalValue
            }
            
            // Reset user input amount when balance changes
            amount = 0.0
            
            updateBalanceLabel()
            objectWillChange.send() // Force UI update after setting values
        } catch {
            print("Error fetching merged balance: \(error)")
            balanceLabel = NSLocalizedString("errorLoadingBalance", comment: "")
            amount = 0
            availableBalance = 0
            totalShares = "0"
            sharePrice = 0
            objectWillChange.send() // Force UI update on error
        }
    }
    
    @MainActor
    private func updateBalanceLabel() {
        balanceLabel = String(format: NSLocalizedString("sharesBalance", comment: ""), availableBalance.formatDecimalToLocale())
        objectWillChange.send() // Force UI update
    }
    
    private func setupValidation() {
        // Validate amount with debounce like in FunctionCallStake
        $amount
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateAmount()
            }
            .store(in: &cancellables)
        
        // Validate selected token
        $selectedToken
            .sink { [weak self] token in
                self?.tokenValid = token.value.lowercased() != NSLocalizedString("theUnmerge", comment: "").lowercased()
            }
            .store(in: &cancellables)
        
        // Overall form validation
        Publishers.CombineLatest3($amountValid, $tokenValid, $fnCallValid)
            .map { $0 && $1 && $2 && !self.amount.isZero }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    private func validateAmount() {
        // Reset error message
        customErrorMessage = nil
        
        // Check if amount is positive
        guard amount > 0 else {
            amountValid = false
            customErrorMessage = NSLocalizedString("enterValidAmount", comment: "")
            return
        }
        
        // Check if amount doesn't exceed available balance
        guard amount <= availableBalance else {
            amountValid = false
            customErrorMessage = NSLocalizedString("insufficientBalanceForFunctions", comment: "Error message when user tries to enter amount greater than available balance")
            return
        }
        
        // Amount is valid
        amountValid = true
        customErrorMessage = nil
    }
    
    func getView() -> AnyView {
        return AnyView(UnmergeView(viewModel: self).onAppear {
            self.initialize()
        })
    }
    
    var formattedBalanceText: String {
        return "\(availableBalance.formatDecimalToLocale()) shares"
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        // Convert decimal shares back to raw amount for memo
        let multiplier = NSDecimalNumber(decimal: pow(Decimal(10), 8))
        let rawShares = amount * multiplier.decimalValue
        let sharesStr = String(format: "%.0f", NSDecimalNumber(decimal: rawShares).doubleValue)
        let memo = "unmerge:\(selectedToken.value.lowercased()):\(sharesStr)"
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", self.destinationAddress)
        dict.set("selectedToken", self.selectedToken.value)
        dict.set("memo", self.toString())
        return dict
    }
}

struct UnmergeView: View {
    @ObservedObject var viewModel: FunctionCallCosmosUnmerge
    
    var body: some View {
        VStack(spacing: 16) {
            GenericSelectorDropDown(
                items: Binding(
                    get: { viewModel.tokens },
                    set: { viewModel.tokens = $0 }
                ),
                selected: Binding(
                    get: { viewModel.selectedToken },
                    set: { viewModel.selectedToken = $0 }
                ),
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    // Reset balance and user input before fetching new one
                    viewModel.amount = 0
                    viewModel.availableBalance = 0
                    viewModel.totalShares = "0"
                    viewModel.sharePrice = 0
                    viewModel.balanceLabel = NSLocalizedString("loading", comment: "")
                    viewModel.customErrorMessage = nil
                    
                    viewModel.selectToken(asset)
                }
            )
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    StyledFloatingPointField(
                        label: viewModel.balanceLabel,
                        placeholder: NSLocalizedString("enterAmountToUnmerge", comment: ""),
                        value: Binding(
                            get: { viewModel.amount },
                            set: {
                                viewModel.amount = $0
                                viewModel.objectWillChange.send()
                            }
                        ),
                        isValid: Binding(
                            get: { viewModel.amountValid },
                            set: { viewModel.amountValid = $0 }
                        )
                    )
                    
                    if let errorMessage = viewModel.customErrorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}
