//
//  SendCryptoVerifyLogic.swift
//  VultisigApp
//
//  Business logic for SendCryptoVerifyViewModel
//

import Foundation
import BigInt
import WalletCore

struct SendCryptoVerifyLogic {
    
    // MARK: - Services
    private let utxo = BlockchairService.shared
    private let blockChainService = BlockChainService.shared
    
    // MARK: - Fee Calculation
    
    struct FeeResult {
        let fee: BigInt
        let gas: BigInt
    }
    
    func calculateFee(tx: SendTransaction) async throws -> FeeResult {
        if tx.coin.chain.chainType == .EVM {
            return try await calculateEVMFee(tx: tx)
        } else {
            return try await calculateNonEVMFee(tx: tx)
        }
    }
    
    private func calculateEVMFee(tx: SendTransaction) async throws -> FeeResult {
        let service = try EthereumFeeService(chain: tx.coin.chain)
        
        let gasLimit = tx.coin.isNativeToken ?
        BigInt(EVMHelper.defaultETHTransferGasUnit) :
        BigInt(EVMHelper.defaultERC20TransferGasUnit)
        
        let feeInfo = try await service.calculateFees(
            chain: tx.coin.chain,
            limit: gasLimit,
            isSwap: false,
            fromAddress: tx.fromAddress,
            feeMode: .default
        )
        
        let fee = feeInfo.amount
        let gas: BigInt
        
        switch feeInfo {
        case .GasFee(let price, _, _, _):
            gas = price
        case .Eip1559(_, let maxFeePerGas, _, _, _):
            gas = maxFeePerGas
        case .BasicFee(let amount, _, let limit):
            if limit > 0 {
                gas = amount / limit
            } else {
                gas = amount
            }
        }
        
        return FeeResult(fee: fee, gas: gas)
    }
    
    private func calculateNonEVMFee(tx: SendTransaction) async throws -> FeeResult {
        let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
        
        let fee: BigInt
        
        switch tx.coin.chain.chainType {
        case .UTXO, .Cardano:
            fee = try await calculateUTXOPlanFee(tx: tx, chainSpecific: chainSpecific)
            
        case .Cosmos, .THORChain:
            fee = chainSpecific.fee
            
        default:
            fee = chainSpecific.gas
        }
        
        return FeeResult(fee: fee, gas: fee)
    }
    
    func calculateUTXOPlanFee(tx: SendTransaction, chainSpecific: BlockChainSpecific) async throws -> BigInt {
        guard let vault = AppViewModel.shared.selectedVault else {
            throw HelperError.runtimeError("No vault available for UTXO fee calculation")
        }
        
        // Normalize decimal separator (replace comma with period for consistent parsing)
        let normalizedAmount = tx.amount.replacingOccurrences(of: ",", with: ".")
        
        // Convert to Decimal and multiply by 10^decimals to get the raw amount
        let amountDecimal = normalizedAmount.toDecimal()
        let multiplier = pow(Decimal(10), tx.coin.decimals)
        let rawAmount = amountDecimal * multiplier
        
        // Convert to BigInt safely using string representation to avoid overflow
        // Convert to BigInt safely using NSDecimalNumber to handle rounding and string conversion
        let rawAmountNumber = NSDecimalNumber(decimal: rawAmount)
        let behavior = NSDecimalNumberHandler(roundingMode: .down, scale: 0, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        let roundedRawAmount = rawAmountNumber.rounding(accordingToBehavior: behavior)
        let rawAmountString = roundedRawAmount.stringValue
        
        guard let actualAmount = BigInt(rawAmountString) else {
            throw HelperError.runtimeError("Invalid amount for fee calculation")
        }
        
        if actualAmount == 0 {
            throw HelperError.runtimeError("Enter an amount to calculate accurate UTXO fees")
        }
        
        // Force fresh UTXO fetch for fee calculation (ONLY for UTXO chains, not Cardano)
        if tx.coin.chain.chainType == .UTXO {
            await BlockchairService.shared.clearUTXOCache(for: tx.coin)
            _ = try await BlockchairService.shared.fetchBlockchairData(coin: tx.coin.toCoinMeta(), address: tx.coin.address)
        }
        // Cardano uses CardanoService.getUTXOs() which is called inside KeysignPayloadFactory
        
        let keysignFactory = KeysignPayloadFactory()
        let keysignPayload = try await keysignFactory.buildTransfer(
            coin: tx.coin,
            toAddress: tx.toAddress.isEmpty ? tx.coin.address : tx.toAddress,
            amount: actualAmount,
            memo: tx.memo.isEmpty ? nil : tx.memo,
            chainSpecific: chainSpecific,
            swapPayload: nil,
            vault: vault
        )
        
        let planFee: BigInt
        
        switch tx.coin.chain {
        case .cardano:
            let cardanoHelper = CardanoHelper()
            planFee = try cardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)
            
        default: // UTXO chains
            guard let utxoHelper = UTXOChainsHelper.getHelper(coin: tx.coin) else {
                throw HelperError.runtimeError("UTXO helper not available for \(tx.coin.chain.name)")
            }
            let plan = try utxoHelper.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
            planFee = BigInt(plan.fee)
        }
        
        if planFee > 0 {
            return planFee
        }
        
        return BigInt.zero
    }
    
    // MARK: - Balance Validation
    
    struct BalanceValidationResult {
        let isValid: Bool
        let errorMessage: String?
    }
    
    func validateBalanceWithFee(tx: SendTransaction) -> BalanceValidationResult {
        let amount = tx.amountInRaw
        let balance = tx.coin.rawBalance.toBigInt(decimals: tx.coin.decimals)
        
        if tx.coin.isNativeToken {
            if tx.sendMaxAmount {
                if tx.fee > balance {
                    return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
                }
            } else {
                let totalAmount = amount + tx.fee
                if totalAmount > balance {
                    return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
                }
            }
        } else {
            if amount > balance {
                return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
            }
            
            // Validate gas balance for non-native tokens
            if let vault = tx.vault ?? AppViewModel.shared.selectedVault {
                if let nativeToken = vault.coins.nativeCoin(chain: tx.coin.chain) {
                    let nativeBalance = nativeToken.rawBalance.toBigInt(decimals: nativeToken.decimals)
                    if tx.fee > nativeBalance {
                        // Using a generic error message since checking gas specifically might require a new error string key
                        // or we can reuse existing logic if available.
                        // The user complained about "walletBalanceExceededError" being shown wrongly,
                        // so returning it for actual insufficient gas is acceptable or we can use "notEnoughGas" if it exists.
                        // But keeping it consistent with the function signature.
                        let nativeToken = vault.coins.nativeCoin(chain: tx.coin.chain)
                        let errorMessage = String(format: "insufficientGasTokenError".localized, nativeToken?.ticker ?? "Native Token", tx.coin.ticker)
                        return BalanceValidationResult(isValid: false, errorMessage: errorMessage)
                    }
                }
            }
        }
        
        return BalanceValidationResult(isValid: true, errorMessage: nil)
    }
    
    // MARK: - UTXO Validation
    
    func validateUtxosIfNeeded(tx: SendTransaction) async throws {
        if tx.coin.chain.chainType == ChainType.UTXO {
            do {
                _ = try await utxo.fetchBlockchairData(coin: tx.coin.toCoinMeta(), address: tx.coin.address)
            } catch {
                print("Failed to fetch UTXO data from Blockchair, error: \(error.localizedDescription)")
                throw HelperError.runtimeError("Failed to fetch UTXO data. Please check your internet connection and try again.")
            }
        }
    }
    
    // MARK: - Keysign Payload
    
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
}
