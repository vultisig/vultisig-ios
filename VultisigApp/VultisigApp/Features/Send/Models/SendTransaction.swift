//
//  SendTransaction.swift
//  VultisigApp
//
//  Immutable hand-off from `SendDetailsViewModel` to the rest of the send
//  flow. Constructed only when the user taps "Continue" and validation
//  passes; consumers (Verify / Pair / Keysign / Done) read it but never
//  mutate it. Form-time mutation lives on the details VM.
//
//  Replaces the legacy `class LegacySendTransaction: ObservableObject` —
//  see [[projects/vultisig/transaction-model-refactor/send-pilot-plan]] for
//  the three kickoff decisions baked in:
//    1. `memoFunctionDictionary` is a plain `[String: String]` (the immutable
//       struct is the thread-safety boundary; no `ThreadSafeDictionary`).
//    2. `vault` is required (`Vault`, not `Vault?`).
//    3. `customGasLimit` / `customByteFee` are first-class fields so the
//       Verify refresh path can preserve them — the legacy
//       `SendCryptoVerifyLogic` dropped the user's pinned gas on refresh.
//

import BigInt
import Foundation
import VultisigCommonData

struct SendTransaction: Hashable {
    // Identity
    let coin: Coin
    let vault: Vault

    // Form fields
    let fromAddress: String
    let toAddress: String
    let toAddressLabel: String?
    let amount: String
    let amountInFiat: String
    let memo: String

    // Fee / gas
    let gas: BigInt
    let fee: BigInt
    let feeMode: FeeMode
    let estimatedGasLimit: BigInt?
    let customGasLimit: BigInt?
    let customByteFee: BigInt?

    // Mode flags
    let sendMaxAmount: Bool
    let isFastVault: Bool
    let isStakingOperation: Bool
    let transactionType: VSTransactionType

    // Function-call side channels (kept as plain fields for the Send pilot;
    // first-class case-enum modelling lands in Functions §13).
    let memoFunctionDictionary: [String: String]
    let wasmContractPayload: WasmExecuteContractPayload?

    /// Native coin that pays for gas — `coin` itself for native sends, the
    /// chain's native sibling (e.g. ETH for a USDC source) otherwise.
    /// Precomputed at construction so Verify/Done don't need the vault's
    /// full coin list at read time.
    let feeCoin: Coin
}

// MARK: - Construction helpers

extension SendTransaction {
    /// Resolve the chain's native coin from the vault (or fall back to the
    /// source coin if the vault doesn't hold a native).
    static func resolveFeeCoin(coin: Coin, vault: Vault) -> Coin {
        guard !coin.isNativeToken else { return coin }
        return vault.coins.nativeCoin(chain: coin.chain) ?? coin
    }

    /// Default-fill an empty SendTransaction for a given coin/vault pair. Used
    /// as the seed for SendDetailsViewModel; real hand-off transactions are
    /// constructed by `SendDetailsViewModel.makeTransaction()` only when the
    /// user taps Continue.
    static func empty(coin: Coin, vault: Vault) -> SendTransaction {
        SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: "",
            toAddressLabel: nil,
            amount: "",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isFastVault: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: resolveFeeCoin(coin: coin, vault: vault)
        )
    }
}

// MARK: - Builder

extension SendTransaction {
    /// Builder for refresh paths in Verify — re-fetched chain-specific / fees
    /// produce a new SendTransaction with the same identity fields.
    ///
    /// `customGasLimit` and `customByteFee` are intentionally NOT clearable
    /// via this builder: if the caller wants to refresh fees but the user
    /// already pinned a custom gas, the pinned value sticks. That's the fix
    /// for the bug where Verify refresh dropped custom gas (decision 3).
    func with(
        gas: BigInt? = nil,
        fee: BigInt? = nil,
        feeMode: FeeMode? = nil,
        estimatedGasLimit: BigInt? = nil,
        memo: String? = nil,
        sendMaxAmount: Bool? = nil,
        memoFunctionDictionary: [String: String]? = nil,
        wasmContractPayload: WasmExecuteContractPayload? = nil
    ) -> SendTransaction {
        SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: fromAddress,
            toAddress: toAddress,
            toAddressLabel: toAddressLabel,
            amount: amount,
            amountInFiat: amountInFiat,
            memo: memo ?? self.memo,
            gas: gas ?? self.gas,
            fee: fee ?? self.fee,
            feeMode: feeMode ?? self.feeMode,
            estimatedGasLimit: estimatedGasLimit ?? self.estimatedGasLimit,
            customGasLimit: customGasLimit,
            customByteFee: customByteFee,
            sendMaxAmount: sendMaxAmount ?? self.sendMaxAmount,
            isFastVault: isFastVault,
            isStakingOperation: isStakingOperation,
            transactionType: transactionType,
            memoFunctionDictionary: memoFunctionDictionary ?? self.memoFunctionDictionary,
            wasmContractPayload: wasmContractPayload ?? self.wasmContractPayload,
            feeCoin: feeCoin
        )
    }
}

// MARK: - Legacy converter (migration-period only)

extension SendTransaction {
    enum LegacyConversionError: Error, LocalizedError {
        case missingVault

        var errorDescription: String? {
            switch self {
            case .missingVault:
                return "Cannot convert LegacySendTransaction: vault unavailable. Either set tx.vault before converting, or pass a vault explicitly via fromLegacy(_:vault:)."
            }
        }
    }

    /// Converts a `LegacySendTransaction` (the old `@Published` ObservableObject)
    /// into the new immutable struct. Resolves the vault via the legacy
    /// `txVault` fallback (`tx.vault ?? AppViewModel.shared.selectedVault`).
    /// Throws if neither is available — non-optional vault is decision 2 of
    /// the Send pilot.
    ///
    /// **Migration-period only.** Delete this extension along with
    /// `LegacySendTransaction` once every call site has migrated.
    static func fromLegacy(_ tx: LegacySendTransaction) throws -> SendTransaction {
        guard let vault = tx.txVault else {
            throw LegacyConversionError.missingVault
        }
        return fromLegacy(tx, vault: vault)
    }

    /// Same as `fromLegacy(_:)` but with the vault supplied explicitly — use
    /// this from contexts where the vault is already in hand (e.g., screens
    /// that received it as a route param).
    static func fromLegacy(_ tx: LegacySendTransaction, vault: Vault) -> SendTransaction {
        SendTransaction(
            coin: tx.coin,
            vault: vault,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            toAddressLabel: tx.toAddressLabel,
            amount: tx.amount,
            amountInFiat: tx.amountInFiat,
            memo: tx.memo,
            gas: tx.gas,
            fee: tx.fee,
            feeMode: tx.feeMode,
            estimatedGasLimit: tx.estematedGasLimit,
            customGasLimit: tx.customGasLimit,
            customByteFee: tx.customByteFee,
            sendMaxAmount: tx.sendMaxAmount,
            isFastVault: tx.isFastVault,
            isStakingOperation: tx.isStakingOperation,
            transactionType: tx.transactionType,
            memoFunctionDictionary: tx.memoFunctionDictionary.allItems(),
            wasmContractPayload: tx.wasmContractPayload,
            feeCoin: resolveFeeCoin(coin: tx.coin, vault: vault)
        )
    }
}

// MARK: - Convenience computed (delegates to SendCryptoLogic)

extension SendTransaction {
    var gasLimit: BigInt {
        customGasLimit ?? estimatedGasLimit ?? BigInt(EVMHelper.defaultETHTransferGasUnit)
    }

    var byteFee: BigInt {
        customByteFee ?? gas
    }

    var amountInRaw: BigInt {
        SendCryptoLogic.amountInRaw(coin: coin, amount: amount)
    }

    var amountDecimal: Decimal {
        SendCryptoLogic.amountDecimal(coin: coin, amount: amount)
    }

    var gasDecimal: Decimal {
        SendCryptoLogic.gasDecimal(gas: gas)
    }

    var isAmountExceeded: Bool {
        SendCryptoLogic.isAmountExceeded(
            coin: coin,
            amount: amount,
            sendMaxAmount: sendMaxAmount,
            fee: fee,
            gas: gas,
            isStakingOperation: isStakingOperation
        )
    }

    var canBeReaped: Bool {
        SendCryptoLogic.canBeReaped(coin: coin, amount: amount, gas: gas)
    }

    var isDeposit: Bool {
        SendCryptoLogic.isDeposit(coin: coin, memoFunctionDictionary: memoFunctionDictionary)
    }

    var gasInReadable: String {
        SendCryptoLogic.gasInReadable(coin: coin, gasNativeCoin: feeCoin, gas: gas, fee: fee)
    }
}
