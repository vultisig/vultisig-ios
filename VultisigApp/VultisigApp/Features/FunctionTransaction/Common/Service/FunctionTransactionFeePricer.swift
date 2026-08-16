//
//  FunctionTransactionFeePricer.swift
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
/// Off EVM the figures come from `SendCryptoVerifyLogic.calculateFee`, the
/// resolver the Send flow's own Verify screen uses: a UTXO/Cardano fee is
/// `rate × the planned size` (the sat/vB rate on `chainSpecific` is a rate, not
/// a fee), and every other chain quotes a flat per-unit gas that IS the whole
/// cost.
///
/// ⚠️ **EVM is priced off the chain-specific fetch the SIGNING path makes**, not
/// off that resolver, and the difference is not cosmetic. A function call is
/// signed from `FunctionTransactionVerifyViewModel.createKeysignPayload` →
/// `BlockChainService.fetchSpecific(tx:)`, whose EVM branch floors every
/// transaction at the 120,000 ERC-20 gas limit. The Send resolver instead
/// floors a native transfer at `Coin.feeDefault` (23,000 on Ethereum). Pricing
/// a native ETH call through the Send resolver therefore discloses as little as
/// `maxFeePerGas × 23,000` for a transaction the vault signs with a limit of
/// 120,000 — understating the fee the user approves, on the screen where they
/// approve it. Reading the same fetch also makes this device agree with the
/// CO-SIGNER, whose `JoinKeysignGasViewModel` prices EVM straight off
/// `payload.chainSpecific.fee` (`maxFeePerGas × gasLimit`).
///
/// It prices the REAL transaction — memo, amount and recipient included — not a
/// bare probe. On EVM that is the difference between the gas limit of the
/// contract call and the 21,000 of a plain transfer.
@MainActor
struct FunctionTransactionFeePricer {
    /// The chain-specific fetch the function-call signing path performs.
    /// Injectable so the disclosure can be tested without a network.
    typealias SigningChainSpecificFetch = (SendTransaction) async throws -> BlockChainSpecific

    private let logic: SendCryptoVerifyLogic
    private let fetchSigningChainSpecific: SigningChainSpecificFetch

    init(
        interactor: SendInteractor = DefaultSendInteractor.live,
        fetchSigningChainSpecific: @escaping SigningChainSpecificFetch = {
            try await BlockChainService.shared.fetchSpecific(tx: $0)
        }
    ) {
        self.logic = SendCryptoVerifyLogic(interactor: interactor)
        self.fetchSigningChainSpecific = fetchSigningChainSpecific
    }

    /// `tx` with both fee figures resolved from the transaction itself.
    ///
    /// Returns `tx` unchanged when the fee cannot be resolved, keeping whatever
    /// the flow already stamped. A fee endpoint that is briefly down is not a
    /// reason to strand the user on a form with no way forward, and the failure
    /// is not silent: it is logged here, and Verify still refuses to sign a
    /// payload it cannot build — on EVM, UTXO and Cardano it is the same fetch
    /// that failed here. The residual is that such a flow discloses the figure
    /// it already had, which is what every one of these seams did
    /// unconditionally before.
    func priced(_ tx: SendTransaction) async -> SendTransaction {
        do {
            if tx.coin.chainType == .EVM {
                let chainSpecific = try await fetchSigningChainSpecific(tx)
                return tx.copy(gas: chainSpecific.gas, fee: chainSpecific.fee)
            }
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
