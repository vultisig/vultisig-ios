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

    // MARK: - Dependencies

    let interactor: SendInteractor

    init(interactor: SendInteractor = DefaultSendInteractor.live) {
        self.interactor = interactor
    }

    // The UTXO + Cardano draft-plan paths still talk to `BlockchairService`
    // and `KeysignPayloadFactory` directly. Refactoring those onto a
    // protocol is a separate step — for now the interactor injection
    // covers the EVM + Cosmos + Solana + TON + other non-UTXO chains,
    // which is what the new tests exercise.
    private var utxo: BlockchairService { .shared }

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
        // Send-pilot decision 3: thread tx.feeMode through instead of
        // hardcoding .default. The user's custom fee mode chosen in the
        // Details screen is otherwise dropped on Verify refresh.
        let result = try await interactor.calculateEVMFee(
            coin: tx.coin,
            fromAddress: tx.fromAddress,
            feeMode: tx.feeMode
        )
        return FeeResult(fee: result.fee, gas: result.gas)
    }

    private func calculateNonEVMFee(tx: SendTransaction) async throws -> FeeResult {
        let chainSpecific = try await interactor.fetchChainSpecific(tx: tx)

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
        // Send-pilot decision 2 win: vault is non-optional on the new struct,
        // so the legacy `AppViewModel.shared.selectedVault` singleton fallback
        // disappears here.
        let vault = tx.vault

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
            planFee = try CardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)

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
        // TRON staking operations: skip balance validation entirely
        // The balance is already validated in TronFreezeView/TronUnfreezeView
        // and the user sees the available balance on the screen
        let isTronStaking = tx.coin.chain == .tron && tx.isStakingOperation

        if isTronStaking {
            return BalanceValidationResult(isValid: true, errorMessage: nil)
        }
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

            // Validate gas balance for non-native tokens. Decision 2 win:
            // vault is now non-optional, so the singleton fallback is gone.
            if let nativeToken = tx.vault.coins.nativeCoin(chain: tx.coin.chain) {
                let nativeBalance = nativeToken.rawBalance.toBigInt(decimals: nativeToken.decimals)
                if tx.fee > nativeBalance {
                    let errorMessage = String(format: "insufficientGasTokenError".localized, nativeToken.ticker, tx.coin.ticker)
                    return BalanceValidationResult(isValid: false, errorMessage: errorMessage)
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
            let chainSpecific = try await interactor.fetchChainSpecific(tx: tx)

            return try await interactor.buildKeysignPayload(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: tx.amountInRaw,
                memo: tx.memo.isEmpty ? nil : tx.memo,
                chainSpecific: chainSpecific,
                wasmExecuteContractPayload: tx.wasmContractPayload,
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
