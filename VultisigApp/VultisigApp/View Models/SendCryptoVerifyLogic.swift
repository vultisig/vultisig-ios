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
    
    func calculateFee(txData: SendTransactionStruct, tx: SendTransaction) async throws -> FeeResult {
        if txData.coin.chain.chainType == .EVM {
            return try await calculateEVMFee(txData: txData)
        } else {
            return try await calculateNonEVMFee(txData: txData, tx: tx)
        }
    }
    
    private func calculateEVMFee(txData: SendTransactionStruct) async throws -> FeeResult {
        let service = try EthereumFeeService(chain: txData.coin.chain)
        let feeInfo = try await service.calculateFees(
            chain: txData.coin.chain,
            limit: BigInt(EVMHelper.defaultETHTransferGasUnit),
            isSwap: false,
            fromAddress: txData.fromAddress,
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
    
    private func calculateNonEVMFee(txData: SendTransactionStruct, tx: SendTransaction) async throws -> FeeResult {
        let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
        
        let fee: BigInt
        
        switch txData.coin.chain.chainType {
        case .UTXO, .Cardano:
            fee = try await calculateUTXOPlanFee(txData: txData, chainSpecific: chainSpecific)
            
        case .Cosmos, .THORChain:
            fee = chainSpecific.fee
            
        default:
            fee = chainSpecific.gas
        }
        
        return FeeResult(fee: fee, gas: fee)
    }
    
    func calculateUTXOPlanFee(txData: SendTransactionStruct, chainSpecific: BlockChainSpecific) async throws -> BigInt {
        guard let vault = ApplicationState.shared.currentVault else {
            throw HelperError.runtimeError("No vault available for UTXO fee calculation")
        }
        
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
    
    // MARK: - Balance Validation
    
    struct BalanceValidationResult {
        let isValid: Bool
        let errorMessage: String?
    }
    
    func validateBalanceWithFee(txData: SendTransactionStruct, fee: BigInt) -> BalanceValidationResult {
        let totalAmount = txData.amount.toBigInt(decimals: txData.coin.decimals) + fee
        if totalAmount > txData.coin.rawBalance.toBigInt(decimals: txData.coin.decimals) {
            return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
        }
        return BalanceValidationResult(isValid: true, errorMessage: nil)
    }
    
    // MARK: - UTXO Validation
    
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

