//
//  UTXOTransactionPlanError.swift
//  VultisigApp
//
//  WalletCore's transaction planner reports WHY it could not build a
//  transaction, in `BitcoinTransactionPlan.error`. This maps that verdict onto
//  a message that names the actual reason.
//

import Foundation
import WalletCore

/// A WalletCore UTXO transaction-plan failure, mapped to an actionable message.
///
/// `UTXOChainsHelper.getBitcoinTransactionPlan` deliberately returns a failed
/// plan untouched: the fee-preview callers (the co-signer gas view, the swap fee
/// preview) tolerate a partial plan and fall back on their own. The callers that
/// must NOT proceed on one — UTXO selection, the Verify-screen fee calculation,
/// the max-send plan — run `validate(_:)` instead, so a planner verdict reaches
/// the user as itself rather than as a blanket "insufficient UTXOs available"
/// (or, worse, as a silent zero fee).
enum UTXOTransactionPlanError: LocalizedError, Equatable {
    /// The spendable outputs cannot cover the requested amount plus the fee.
    case insufficientFunds
    /// What would be left for the recipient is below the network's dust limit.
    case dustAmount
    /// The planner was handed a zero amount.
    case zeroAmount
    /// The plan needs more inputs than a single transaction may carry.
    case transactionTooLarge
    /// One of the supplied outputs is unusable (malformed or wrong amount).
    case invalidUtxo
    /// Any other planner verdict. Carries the raw WalletCore code so a bug
    /// report can name it instead of describing a symptom.
    case planningFailed(code: String)

    var errorDescription: String? {
        switch self {
        case .insufficientFunds:
            return "utxoPlanInsufficientFundsError".localized
        case .dustAmount:
            return "utxoPlanDustAmountError".localized
        case .zeroAmount:
            return "utxoPlanZeroAmountError".localized
        case .transactionTooLarge:
            return "utxoPlanTransactionTooLargeError".localized
        case .invalidUtxo:
            return "utxoPlanInvalidUtxoError".localized
        case .planningFailed(let code):
            return String(format: "utxoPlanFailedError".localized, code)
        }
    }

    /// Throws when WalletCore reported a planning failure; returns for `.ok`.
    static func validate(_ plan: BitcoinTransactionPlan) throws {
        if let error = mapped(plan.error) {
            throw error
        }
    }

    /// `nil` for `.ok` — every other verdict maps to a case. Unknown codes
    /// (including protobuf's `UNRECOGNIZED`) fall through to
    /// `.planningFailed`, so a WalletCore upgrade that adds a code degrades to
    /// a named-code message rather than silently passing as success.
    static func mapped(_ error: CommonSigningError) -> UTXOTransactionPlanError? {
        switch error {
        case .ok:
            return nil
        case .errorLowBalance, .errorNotEnoughUtxos, .errorMissingInputUtxos:
            return .insufficientFunds
        case .errorDustAmountRequested:
            return .dustAmount
        case .errorZeroAmountRequested:
            return .zeroAmount
        case .errorTxTooBig:
            return .transactionTooLarge
        case .errorInvalidUtxo, .errorInvalidUtxoAmount:
            return .invalidUtxo
        default:
            return .planningFailed(code: String(describing: error))
        }
    }
}
