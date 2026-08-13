//
//  FunctionCallFeePricer.swift
//  VultisigApp
//
//  The one place a function-call transaction gets its network fee, between the
//  form and the Verify screen that discloses it.
//

import Foundation
import OSLog

private let logger = Log.send.service

/// Prices the transaction a function-call flow is about to put on Verify, and
/// stamps BOTH fee figures onto it.
///
/// ⚠️ **Both figures, always — the fee row and the fiat figure beside it read
/// different ones.** `SendCryptoLogic.displayFee` reads `fee` on EVM, UTXO and
/// Cardano and `gas` everywhere else, and `CryptoAmountFormatter.feesInReadable`
/// reads `fee` on every chain. A hand-off that fetches the chain-specific data
/// and stamps only `gas` therefore discloses `0` on exactly the chains whose fee
/// is largest: the user approves a fee they were never shown, and signing then
/// re-fetches a real one and charges it. That is why this exists as a shared
/// step instead of a `chainSpecific.gas` copy repeated at each navigation seam —
/// there were three of them, and every one of them was wrong the same way.
///
/// The figures come from `SendCryptoVerifyLogic.calculateFee`, the resolver the
/// Send flow's own Verify screen uses, so a function call is priced the way a
/// send is: an EVM fee is `maxFeePerGas × the limit estimated for THIS call`, a
/// UTXO/Cardano fee is `rate × the planned size` (the sat/vB rate on its own is
/// a rate, not a fee), and every other chain quotes a flat per-unit gas that IS
/// the whole cost. Mirroring it is what makes "what Verify says" and "what
/// signing charges" the same number.
///
/// It prices the REAL transaction — memo, amount and recipient included — not a
/// bare probe. On EVM that is the difference between the gas limit of the
/// contract call and the 21,000 of a plain transfer.
@MainActor
struct FunctionCallFeePricer {
    private let logic: SendCryptoVerifyLogic

    init(interactor: SendInteractor = DefaultSendInteractor.live) {
        self.logic = SendCryptoVerifyLogic(interactor: interactor)
    }

    /// `tx` with both fee figures resolved from the transaction itself.
    ///
    /// Returns `tx` unchanged when the fee cannot be resolved, keeping whatever
    /// the flow already stamped. A fee endpoint that is briefly down is not a
    /// reason to strand the user on a form with no way forward, and the failure
    /// is not silent: it is logged here, and Verify still refuses to sign a
    /// payload it cannot build. The residual is that such a flow discloses the
    /// figure it already had — which is what every one of these seams did
    /// unconditionally before.
    func priced(_ tx: SendTransaction) async -> SendTransaction {
        do {
            let result = try await logic.calculateFee(tx: tx)
            return tx.copy(gas: result.gas, fee: result.fee)
        } catch {
            logger.error(
                "failed to price a function-call transaction: \(error.localizedDescription, privacy: .public)"
            )
            return tx
        }
    }
}
