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
        let result = try await interactor.calculateEVMFee(SendFeeEstimateRequest(tx: tx))
        return FeeResult(fee: result.fee, gas: result.gas)
    }

    private func calculateNonEVMFee(tx: SendTransaction) async throws -> FeeResult {
        let chainSpecific = try await interactor.fetchChainSpecific(tx: tx)

        var fee: BigInt

        switch tx.coin.chain.chainType {
        case .UTXO, .Cardano:
            fee = try await interactor.calculatePlanFee(tx: tx, chainSpecific: chainSpecific)

        case .Cosmos, .THORChain:
            // Cosmos batched-claim signs one msg per validator and the
            // resolver scales gas + fee linearly. Mirror that scaling here
            // so the Verify summary and the balance-validation check both
            // reflect the real signed fee, not the single-msg base. Any
            // other staking op is 1 msg → multiplier collapses to 1.
            fee = chainSpecific.fee
            if let payload = tx.cosmosStakingPayload,
               payload.opType == .withdrawRewards,
               let count = payload.validators?.count, count > 1 {
                fee *= BigInt(count)
            }

        default:
            fee = chainSpecific.gas
        }

        return FeeResult(fee: fee, gas: fee)
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
        } else if tx.coin.chain == .terraClassic
                    && TerraClassicTax.isBankDenom(
                        contractAddress: tx.coin.contractAddress,
                        isNativeToken: tx.coin.isNativeToken
                    ) {
            // Terra Classic bank-denom tokens (USTC / uusd) pay their gas + burn
            // tax in the SAME denom they're sending, so the fee comes out of the
            // token balance — not the native LUNC balance. Validate amount + fee
            // against the token balance and skip the native-gas check below.
            // CW20 (terra1…) and IBC (ibc/…) Terra Classic tokens pay the fee in
            // native LUNC, so they fall through to the generic non-native branch.
            let totalAmount = tx.sendMaxAmount ? tx.fee : amount + tx.fee
            if totalAmount > balance {
                return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
            }
        } else {
            if amount > balance {
                return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
            }

            // Cardano native-token sends must fund both the recipient output
            // and the change output at the protocol min-UTXO floor (~1.4 ADA
            // each, Alonzo era), in addition to the fee. Surface a dedicated
            // error when the vault's ADA balance can't cover that.
            if tx.coin.chain == .cardano,
               let nativeToken = tx.vault.coins.nativeCoin(chain: .cardano) {
                let nativeBalance = nativeToken.rawBalance.toBigInt(decimals: nativeToken.decimals)
                let minAdaReserve = CardanoHelper.defaultMinUTXOValue * 2
                if nativeBalance < tx.fee + minAdaReserve {
                    return BalanceValidationResult(isValid: false, errorMessage: "cardanoOutputBelowMinAda")
                }
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
        try await interactor.validateUtxosIfNeeded(coin: tx.coin)
    }

    // MARK: - Keysign Payload

    func buildKeysignPayload(tx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        do {
            let chainSpecific = try await interactor.fetchChainSpecific(tx: tx)

            let basePayload = try await interactor.buildKeysignPayload(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: tx.amountInRaw,
                memo: tx.memo.isEmpty ? nil : tx.memo,
                chainSpecific: chainSpecific,
                wasmExecuteContractPayload: tx.wasmContractPayload,
                vault: vault
            )

            // Cosmos staking branch — when the per-flow builder produced a
            // `cosmosStakingPayload`, swap the base payload's `signData` for
            // a freshly-resolved `.signDirect(...)` carrying the proto-encoded
            // MsgDelegate / MsgUndelegate / MsgBeginRedelegate /
            // MsgWithdrawDelegatorReward bytes. The SignDoc is the contract
            // the peer device sees; everything else on `KeysignPayload`
            // becomes descriptive (verify-summary) only.
            if tx.cosmosStakingPayload != nil {
                let signDirect = try CosmosStakingSignDataResolver.resolve(
                    sendTransaction: tx,
                    chainSpecific: chainSpecific
                )
                return basePayload.withSignData(.signDirect(signDirect))
            }

            return basePayload

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
