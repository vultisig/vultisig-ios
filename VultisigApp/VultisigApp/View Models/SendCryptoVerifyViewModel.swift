//
//  SendCryptoVerifyViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-19.
//

import SwiftUI
import BigInt
import WalletCore


@MainActor
class SendCryptoVerifyViewModel: ObservableObject {
    let securityScanViewModel = SecurityScannerViewModel()
    
    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var showAlert = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    @Published var showSecurityScannerSheet: Bool = false
    @Published var securityScannerState: SecurityScannerState = .idle
    
    private let utxo = BlockchairService.shared
    private let blockChainService = BlockChainService.shared
    
    // Services for fee calculation
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let ton = TonService.shared
    private let ripple = RippleService.shared
    private let tron = TronService.shared
    private let balanceService = BalanceService.shared
    
    func onLoad() {
        securityScanViewModel.$state
            .assign(to: &$securityScannerState)
    }
    
    func loadGasInfoForSending(txData: SendTransactionStruct, tx: SendTransaction) async {
        tx.isCalculatingFee = true
        self.isLoading = true
        self.errorMessage = ""
        
        do {
            if txData.coin.chain.chainType == .EVM {
                let service = try EthereumFeeService(chain: txData.coin.chain)
                let feeInfo = try await service.calculateFees(
                    chain: txData.coin.chain,
                    limit: BigInt(EVMHelper.defaultETHTransferGasUnit),
                    isSwap: false,
                    fromAddress: txData.fromAddress,
                    feeMode: .default
                )
                
                await MainActor.run {
                    tx.fee = feeInfo.amount
                    
                    switch feeInfo {
                    case .GasFee(let price, _, _, _):
                        tx.gas = price
                    case .Eip1559(_, let maxFeePerGas, _, _, _):
                        tx.gas = maxFeePerGas
                    case .BasicFee(let amount, _, let limit):
                         if limit > 0 {
                            tx.gas = amount / limit
                         } else {
                            tx.gas = amount
                         }
                    }
                    
                    tx.isCalculatingFee = false
                    self.isLoading = false
                    self.validateBalanceWithFee(txData: txData, tx: tx)
                }
            } else {
                // Fetch chain-specific data
                let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
                
                let fee: BigInt
                
                // Determine fee based on chain type
                switch txData.coin.chain.chainType {
                case .UTXO, .Cardano:
                    // For UTXO chains, we need to calculate the plan fee
                    fee = try await calculateUTXOPlanFee(txData: txData, chainSpecific: chainSpecific)
                    
                case .Cosmos, .THORChain:
                    // For Cosmos-based chains (including MayaChain), the fee is already in chainSpecific
                    fee = chainSpecific.fee
                    
                default:
                    // For other chains, use the gas value from chainSpecific
                    fee = chainSpecific.gas
                }
                
                await MainActor.run {
                    tx.fee = fee
                    tx.gas = fee
                    tx.isCalculatingFee = false
                    self.isLoading = false
                    self.validateBalanceWithFee(txData: txData, tx: tx)
                }
            }
        } catch {
            print("DEBUG: Error calculating fee: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showAlert = true
                tx.isCalculatingFee = false
                self.isLoading = false
            }
        }
    }
    
    func calculateUTXOPlanFee(txData: SendTransactionStruct, chainSpecific: BlockChainSpecific) async throws -> BigInt {
        guard let vault = ApplicationState.shared.currentVault else {
            throw HelperError.runtimeError("No vault available for UTXO fee calculation")
        }
        
        // Don't calculate plan fee if amount is 0 or empty
        // Normalize decimal separator (replace comma with period for consistent parsing)
        let normalizedAmount = txData.amount.replacingOccurrences(of: ",", with: ".")
        
        // Convert to Decimal and multiply by 10^decimals to get the raw amount
        let amountDecimal = normalizedAmount.toDecimal()
        let multiplier = pow(Decimal(10), txData.coin.decimals)
        let rawAmount = amountDecimal * multiplier
        let actualAmount = BigInt(NSDecimalNumber(decimal: rawAmount).int64Value)
        
        if actualAmount == 0 {
            throw HelperError.runtimeError("Enter an amount to calculate accurate UTXO fees")
        }
        
        // Force fresh UTXO fetch for fee calculation (ONLY for UTXO chains, not Cardano)
        if txData.coin.chain.chainType == .UTXO {
            await BlockchairService.shared.clearUTXOCache(for: txData.coin)
            let _ = try await BlockchairService.shared.fetchBlockchairData(coin: txData.coin)
        }
        // Cardano uses CardanoService.getUTXOs() which is called inside KeysignPayloadFactory
        
        let keysignFactory = KeysignPayloadFactory()
        let keysignPayload = try await keysignFactory.buildTransfer(
            coin: txData.coin,
            toAddress: txData.toAddress.isEmpty ? txData.coin.address : txData.toAddress,
            amount: actualAmount,
            memo: txData.memo.isEmpty ? nil : txData.memo,
            chainSpecific: chainSpecific,
            swapPayload: nil,
            vault: vault
        )
        
        let planFee: BigInt
        
        switch txData.coin.chain {
        case .cardano:
            let cardanoHelper = CardanoHelper()
            planFee = try cardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)
            
        default: // UTXO chains
            guard let utxoHelper = UTXOChainsHelper.getHelper(coin: txData.coin) else {
                throw HelperError.runtimeError("UTXO helper not available for \(txData.coin.chain.name)")
            }
            let plan = try utxoHelper.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
            planFee = BigInt(plan.fee)
        }
        
        if planFee > 0 {
            return planFee
        }
        
        return BigInt.zero
    }
    
    func validateBalanceWithFee(txData: SendTransactionStruct, tx: SendTransaction) {
        let totalAmount = txData.amount.toBigInt(decimals: txData.coin.decimals) + tx.fee
        if totalAmount > txData.coin.rawBalance.toBigInt(decimals: txData.coin.decimals) {
            errorMessage = "walletBalanceExceededError"
            showAlert = true
            isAmountCorrect = false // Reset confirmation if balance exceeded
        }
    }
    
    var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect
    }
    
    var signButtonDisabled: Bool {
        !isValidForm || isLoading
    }
    
    func validateForm(tx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        await MainActor.run { isLoading = true }
        do {
            if !isValidForm {
                throw HelperError.runtimeError("mustAgreeTermsError")
            }
            
            try await validateUtxosIfNeeded(tx: tx)
            let keysignPayload = try await buildKeysignPayload(tx: tx, vault: vault)
            await MainActor.run { isLoading = false }
            return keysignPayload
        } catch {
            await MainActor.run { isLoading = false }
            throw error
        }
    }
    
    func validateUtxosIfNeeded(tx: SendTransaction) async throws {
        if tx.coin.chain.chainType == ChainType.UTXO {
            do {
                _ = try await utxo.fetchBlockchairData(coin: tx.coin)
            } catch {
                print("Failed to fetch UTXO data from Blockchair, error: \(error.localizedDescription)")
                throw HelperError.runtimeError("Failed to fetch UTXO data. Please check your internet connection and try again.")
            }
        }
    }
    
    func buildKeysignPayload(tx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
            
            return try await KeysignPayloadFactory().buildTransfer(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: tx.amountInRaw,
                memo: tx.memo,
                chainSpecific: chainSpecific,
                vault: vault
            )
            
        } catch {
            // Handle UTXO-specific errors with more user-friendly messages
            let errorMessage: String
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughUTXOError:
                errorMessage = NSLocalizedString("notEnoughUTXOError", comment: "")
            case KeysignPayloadFactory.Errors.utxoTooSmallError:
                errorMessage = NSLocalizedString("utxoTooSmallError", comment: "")
            case KeysignPayloadFactory.Errors.utxoSelectionFailedError:
                errorMessage = NSLocalizedString("utxoSelectionFailedError", comment: "")
            case KeysignPayloadFactory.Errors.notEnoughBalanceError:
                errorMessage = NSLocalizedString("notEnoughBalanceError", comment: "")
            default:
                errorMessage = error.localizedDescription
            }
            throw HelperError.runtimeError(errorMessage)
        }
    }
    
    func scan(transaction: SendTransaction, vault: Vault) async {
        await securityScanViewModel.scan(transaction: transaction, vault: vault)
    }
    
    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }
}
