//
//  PrebuiltPayloadFee.swift
//  VultisigApp
//

import BigInt
import Foundation

/// The fee a pre-built keysign payload will actually be charged.
///
/// The verify screen normally derives its fee row by re-estimating from the
/// `SendTransaction` it is showing. For a flow that pre-built its payload —
/// Kamino, Circle, Yield — that transaction is display-only: it names the asset,
/// the amount and the destination so the summary reads correctly, and it is
/// explicitly NOT the thing being signed. Re-estimating from it therefore
/// answers a question nobody asked, and the number it produces can differ from
/// the one inside the bytes.
///
/// Kamino is where the missing term is visible. Its transactions carry an
/// injected ComputeBudget pair whose cost is `limit × price` micro-lamports —
/// up to 0.00035 SOL at the clamp ceiling — and `BlockChainSpecific.Solana.gas`
/// does not account for it at all.
///
/// What it accounts for instead is `SolanaHelper.defaultFeeInLamports`, a flat
/// 0.001 SOL the app quotes for **every** Solana transaction. That flat figure
/// is deliberately conservative and it is app-wide, so it stays the base here:
/// replacing it with the true per-signature fee for this one flow would make
/// Kamino the only Solana screen quoting on a different basis, which is a
/// repo-wide decision and not this feature's to make. The change is additive —
/// the term the payload records and the display ignored is added to the term
/// the display already had.
///
/// This reads the payload's own `chainSpecific` — the record of what was built —
/// rather than re-deriving anything.
enum PrebuiltPayloadFee {

    /// Micro-lamports per compute unit; the ComputeBudget price is quoted in
    /// these and a lamport is a million of them.
    private static let microLamportsPerLamport = BigInt(1_000_000)

    /// The fee `payload` describes, or `nil` when its `chainSpecific` carries
    /// nothing better than the generic estimate — in which case the caller keeps
    /// the estimate rather than substituting a worse number.
    static func fee(for payload: KeysignPayload) -> BigInt? {
        switch payload.chainSpecific {
        case .Solana(_, let priorityFee, let priorityLimit, _, _, _):
            let base = payload.chainSpecific.fee
            guard priorityFee > 0, priorityLimit > 0 else { return base }
            // Integer division, rounding up: the network charges for a whole
            // lamport, and a fee row that rounded down would under-report the
            // charge by up to one lamport for the same reason it exists.
            let priority = priorityFee * priorityLimit
            let rounded = (priority + microLamportsPerLamport - 1) / microLamportsPerLamport
            return base + rounded

        case .Ethereum, .UTXO, .Cardano, .THORChain, .MayaChain, .Cosmos,
             .Sui, .Polkadot, .Ton, .Ripple, .Tron:
            // Every other pre-built flow's `chainSpecific.fee` is already the
            // total the signer pays, so it is used as-is. A zero means the
            // payload was built without a fee estimate, and the caller's own
            // estimate is then the better answer.
            let fee = payload.chainSpecific.fee
            return fee > 0 ? fee : nil
        }
    }
}
