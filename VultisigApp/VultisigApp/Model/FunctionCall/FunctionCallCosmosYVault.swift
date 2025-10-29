//
//  FunctionCallCosmosYVault.swift
//  VultisigApp
//

import SwiftUI
import Foundation
import Combine
import VultisigCommonData

struct YVaultConstants {
    private static let yRuneContract = "thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt"
    private static let yTcyContract = "thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px"
    
    // Affiliate contract configuration for 10 basis points (0.1%) fees
    static let affiliateContractAddress = "thor1v3f7h384r8hw6r3dtcgfq6d5fq842u6cjzeuu8nr0cp93j7zfxyquyrfl8"
    static let affiliateAddress = "thor1svfwxevnxtm4ltnw92hrqpqk4vzuzw9a4jzy04" // Your affiliate address
    static let affiliateFeeBasisPoints = 10 // 10 basis points = 0.1%
    
    static let contracts: [String: String] = [
        "rune": yRuneContract,
        "tcy": yTcyContract,
        "yrune": yRuneContract,
        "ytcy": yTcyContract
    ]
    
    static let receiptDenominations: [String: String] = [
        "rune": "x/nami-index-nav-\(yRuneContract)-rcpt",
        "tcy": "x/nami-index-nav-\(yTcyContract)-rcpt",
        "yrune": "x/nami-index-nav-\(yRuneContract)-rcpt",
        "ytcy": "x/nami-index-nav-\(yTcyContract)-rcpt"
    ]
    
    static let slippageOptions: [Decimal] = [0.01, 0.02, 0.05, 0.075]
    
    static let actionLabels: [String: String] = [
        "rune": "Receive yRUNE",
        "tcy": "Receive yTCY",
        "yrune": "Sell yRUNE",
        "ytcy": "Sell yTCY"
    ]
}

enum YVaultAction {
    case deposit
    case withdraw(slippage: Decimal)
}

class FunctionCallCosmosYVault: ObservableObject {
    @Published var amount: Decimal = 0.0 { didSet { recalcMicroAmount() } }
    @Published var amountValid = false
    @Published var isTheFormValid = false
    @Published var customErrorMessage: String? = nil
    @Published var balanceLabel = "( Balance: -- )"
    @Published var selectedSlippage: Decimal = YVaultConstants.slippageOptions.first!
    @Published var destinationAddress: String = ""
    @Published var action: YVaultAction
    
    @ObservedObject var tx: SendTransaction
    private let vault: Vault
    private let contractAddress: String
    
    private var amountMicro: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()
    init(tx: SendTransaction, vault: Vault, action: YVaultAction, functionType: FunctionCallType? = nil) {
        self.vault = vault
        
        // Determine the correct coin based on function type
        let finalTx: SendTransaction
        if let functionType = functionType {
            let correctCoin = Self.getCorrectCoin(for: functionType, from: vault, currentCoin: tx.coin)
            finalTx = tx
            finalTx.coin = correctCoin
        } else {
            finalTx = tx
        }
        
        self.tx = finalTx
        let denom = finalTx.coin.ticker.lowercased()
        self.contractAddress = YVaultConstants.contracts[denom] ?? ""
        self.destinationAddress = YVaultConstants.affiliateContractAddress // Use affiliate contract as destination
        
        if denom == "rune" || denom == "tcy" {
            self.action = .deposit
        } else if denom == "yrune" || denom == "ytcy" {
            if case .withdraw(let slip) = action {
                self.action = .withdraw(slippage: slip)
            } else {
                self.action = .withdraw(slippage: YVaultConstants.slippageOptions.first!)
            }
        } else {
            self.action = .withdraw(slippage: YVaultConstants.slippageOptions.first!)
        }
        
        setupValidation()
    }
    
    private static func getCorrectCoin(for functionType: FunctionCallType, from vault: Vault, currentCoin: Coin) -> Coin {
        switch functionType {
        case .mintYRune:
            // Need RUNE coin to mint yRUNE
            return vault.coins.first { $0.ticker.uppercased() == "RUNE" && $0.chain == .thorChain } ?? currentCoin
        case .mintYTCY:
            // Need TCY coin to mint yTCY
            return vault.coins.first { $0.ticker.uppercased() == "TCY" && $0.chain == .thorChain } ?? currentCoin
        case .redeemRune:
            // Need yRUNE coin to redeem RUNE
            return vault.coins.first { $0.ticker.uppercased() == "YRUNE" && $0.chain == .thorChain } ?? currentCoin
        case .redeemTCY:
            // Need yTCY coin to redeem TCY
            return vault.coins.first { $0.ticker.uppercased() == "YTCY" && $0.chain == .thorChain } ?? currentCoin
        default:
            return currentCoin
        }
    }
    
    func initiate() {
        balanceLabel = "( Balance: \(tx.coin.balanceDecimal.formatForDisplay()) \(tx.coin.ticker.uppercased()) )"
        if case .withdraw(let slip) = self.action { selectedSlippage = slip }
        validateAmount()
    }
    
    private func setupValidation() {
        $amount
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] newAmount in
                self?.validateAmount()
            }
            .store(in: &cancellables)
        
        $amountValid.assign(to: \.isTheFormValid, on: self).store(in: &cancellables)
        
        // Watch for coin changes and re-initiate when it changes
        tx.objectWillChange
            .sink { [weak self] (_: Void) in
                DispatchQueue.main.async {
                    self?.initiate()
                }
            }
            .store(in: &cancellables)
    }
    
    private func validateAmount() {
        let balance = tx.coin.balanceDecimal
        let isValidAmount = amount > 0 && amount <= balance
        amountValid = isValidAmount
        
        if balance < amount {
            amountValid = false
            self.customErrorMessage = NSLocalizedString("insufficientBalanceForFunctions", comment: "Error message when user tries to enter amount greater than available balance")
        }
    }
    
    private func recalcMicroAmount() {
        let decimals = tx.coin.decimals
        let multiplier = pow(10.0, Double(decimals))
        let micro = (amount * Decimal(multiplier)) as NSDecimalNumber
        amountMicro = micro.uint64Value
    }
    
    private func buildExecuteMsg() -> String {
        let denom = tx.coin.ticker.lowercased()
        let targetContract = YVaultConstants.contracts[denom] ?? ""
        
        switch action {
        case .deposit:
            let depositMsg = "{\"deposit\":{}}"
            let base64Msg = Data(depositMsg.utf8).base64EncodedString()
            return "{\"execute\":{\"contract_addr\":\"\(targetContract)\",\"msg\": \"\(base64Msg)\",\"affiliate\":[\"\(YVaultConstants.affiliateAddress)\",\(YVaultConstants.affiliateFeeBasisPoints)]}}"
            
        case .withdraw(let slippage):
            let slipStr = String(describing: slippage)
            let withdrawMsg = "{\"withdraw\":{\"slippage\":\"\(slipStr)\"}}"
            let base64Msg = Data(withdrawMsg.utf8).base64EncodedString()
            return "{\"execute\":{\"contract_addr\":\"\(targetContract)\",\"msg\": \"\(base64Msg)\",\"affiliate\":[\"\(YVaultConstants.affiliateAddress)\",\(YVaultConstants.affiliateFeeBasisPoints)]}}"
        }
    }
    
    var wasmContractPayload: WasmExecuteContractPayload {
        let cosmosCoin: CosmosCoin

        switch action {
        case .deposit:
            let denomKey = tx.coin.ticker.lowercased()
            cosmosCoin = CosmosCoin(amount: String(amountMicro), denom: denomKey)
        case .withdraw:
            let denomKey = tx.coin.ticker.lowercased()
            let receiptDenom = YVaultConstants.receiptDenominations[denomKey] ?? ""
            cosmosCoin = CosmosCoin(amount: String(amountMicro), denom: receiptDenom)
        }

        return WasmExecuteContractPayload(
            senderAddress: tx.coin.address,
            contractAddress: destinationAddress,
            executeMsg: buildExecuteMsg(),
            coins: [cosmosCoin]
        )
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("executeMsg", buildExecuteMsg())
        return dict
    }
    
    var description: String { "yVault-\(tx.coin.ticker.uppercased())-\(actionStr)" }
    private var actionStr: String { action.isDeposit ? "deposit" : "withdraw" }
    
    var toAddress: String? {
        return destinationAddress
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallCosmosYVaultView(viewModel: self).onAppear{
            self.initiate()
        })
    }
}

private extension YVaultAction {
    var isDeposit: Bool {
        if case .deposit = self { return true } else { return false }
    }
}

struct FunctionCallCosmosYVaultView: View {
    @ObservedObject var viewModel: FunctionCallCosmosYVault
    
    var body: some View {
        VStack {
            GenericSelectorDropDown(
                items: Binding(
                    get: {
                        let ticker = viewModel.tx.coin.ticker.lowercased()
                        let label = YVaultConstants.actionLabels[ticker] ?? "Unsupported"
                        return [IdentifiableString(value: label)]
                    },
                    set: { _ in }
                ),
                selected: Binding(
                    get: {
                        let ticker = viewModel.tx.coin.ticker.lowercased()
                        let label = YVaultConstants.actionLabels[ticker] ?? "Unsupported"
                        return IdentifiableString(value: label)
                    },
                    set: { sel in
                        if sel.value.contains("Receive") {
                            viewModel.action = .deposit
                        } else if sel.value.contains("Sell") {
                            viewModel.action = .withdraw(slippage: viewModel.selectedSlippage)
                        }
                    }
                ),
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { _ in }
            )
            .padding(.bottom, 8)
            
            StyledFloatingPointField(
                label: "Amount \(viewModel.balanceLabel)",
                placeholder: NSLocalizedString("enterAmount", comment: ""),
                value: Binding(
                    get: { viewModel.amount },
                    set: { viewModel.amount = $0 }
                ),
                isValid: Binding(
                    get: { viewModel.amountValid },
                    set: { _ in }
                ),
                isOptional: false
            )
            
            if case .withdraw = viewModel.action {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Slippage")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(Theme.colors.textPrimary)
                    
                    GenericSelectorDropDown(
                        items: Binding(
                            get: { YVaultConstants.slippageOptions.map { IdentifiableString(value: "\($0 * 100)%") } },
                            set: { _ in }
                        ),
                        selected: Binding(
                            get: { IdentifiableString(value: "\(viewModel.selectedSlippage * 100)%") },
                            set: { sel in
                                if let val = Decimal(string: sel.value.replacingOccurrences(of: "%", with: "")) {
                                    viewModel.selectedSlippage = val / 100
                                    viewModel.action = .withdraw(slippage: viewModel.selectedSlippage)
                                }
                            }
                        ),
                        mandatoryMessage: "*",
                        descriptionProvider: { $0.value },
                        onSelect: { _ in }
                    )
                }
            }
        }
    }
}
