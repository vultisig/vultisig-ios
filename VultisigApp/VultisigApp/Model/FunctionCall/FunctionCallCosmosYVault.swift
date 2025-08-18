//
//  FunctionCallCosmosYVault.swift
//  VultisigApp
//

import SwiftUI
import Foundation
import Combine

struct YVaultConstants {
    private static let yRuneContract = "thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt"
    private static let yTcyContract = "thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px"
    
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
    
    static let depositMsgJSON = "{ \"deposit\": {} }"
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
    @Published var balanceLabel = "( Balance: -- )"
    @Published var selectedSlippage: Decimal = YVaultConstants.slippageOptions.first!
    @Published var destinationAddress: String = ""
    @Published var action: YVaultAction
    
    @ObservedObject var tx: SendTransaction
    private let vault: Vault
    private let contractAddress: String
    
    private var amountMicro: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()
    init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault, action: YVaultAction) {
        self.tx = tx
        self.vault = vault
        let denom = tx.coin.ticker.lowercased()
        self.contractAddress = YVaultConstants.contracts[denom] ?? ""
        self.destinationAddress = self.contractAddress
        
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
        
        $amountValid.assign(to: \Self.isTheFormValid, on: self).store(in: &cancellables)
    }
    
    private func validateAmount() {
        let balance = tx.coin.balanceDecimal
        let isValidAmount = amount > 0 && amount <= balance
        amountValid = isValidAmount
    }
    
    private func recalcMicroAmount() {
        let decimals = tx.coin.decimals
        let multiplier = pow(10.0, Double(decimals))
        let micro = (amount * Decimal(multiplier)) as NSDecimalNumber
        amountMicro = micro.uint64Value
    }
    
    private func buildExecuteMsg() -> String {
        switch action {
        case .deposit:
            return YVaultConstants.depositMsgJSON
        case .withdraw(let slippage):
            let slipStr = String(describing: slippage)
            return "{ \"withdraw\": { \"slippage\": \"\(slipStr)\" } }"
        }
    }
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", destinationAddress)
        dict.set("executeMsg", buildExecuteMsg())
        
        let denomKey = tx.coin.ticker.lowercased()
        switch action {
        case .deposit:
            dict.set("denom", denomKey)
        case .withdraw:
            let receiptDenom = YVaultConstants.receiptDenominations[denomKey] ?? ""
            dict.set("denom", receiptDenom)
        }
        
        dict.set("amount", String(amountMicro))
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
