//
//  SpendableUtxos.swift
//  VultisigApp
//

import BigInt
import Foundation

/// The single definition of which of an address's unspent outputs this wallet
/// treats as its own spendable money on the Blockchair-backed UTXO chains.
///
/// Both numbers the user meets come from here: the balance on the wallet
/// screen (`BalanceService`) and the candidate set a transaction is funded
/// from (`KeysignPayloadFactory`). They used to be derived independently — the
/// balance from Blockchair's `address.balance`, the inputs from a separately
/// filtered `utxo` array — and everything in the gap between them was money
/// the wallet displayed and then refused to spend: a send cleared the balance
/// check and failed at input selection, and send-max drained less than the
/// screen showed. One predicate with two callers is what keeps that gap shut.
enum SpendableUtxos {

    /// Narrows Blockchair's rows to the outputs that may fund a transaction.
    ///
    /// - **Not explicitly unspendable.** `is_spendable` is absent from
    ///   Blockchair's Bitcoin responses, so absent means spendable and only an
    ///   explicit `false` disqualifies an output — the SDK's
    ///   `is_spendable !== false`.
    /// - **Confirmed, or unconfirmed and ours.** Blockchair reports mempool
    ///   outputs with `block_id == -1` and counts them in `address.balance`.
    ///   Zero-conf someone else controls can be replaced or evicted at will,
    ///   and the MPC pairing window leaves minutes for that between selection
    ///   and broadcast, so a child built on it can die with its parent.
    ///   Zero-conf produced by a transaction *this device* broadcast for
    ///   *this vault* is a different animal: only this wallet can spend that
    ///   parent's inputs, so nobody else can replace it. That split is
    ///   Bitcoin Core's own policy — spend your own unconfirmed change, never
    ///   someone else's. Withholding it instead would blank the wallet for a
    ///   block after every send, because the input leaves the UTXO set the
    ///   moment the parent reaches the mempool while the change arrives
    ///   unconfirmed.
    /// - **At or above the chain's dust threshold.** Deliberately inclusive
    ///   (`>=`) rather than the SDK's strict `>`: that boundary predates this
    ///   filter and tightening it would drop outputs this app can spend today.
    ///
    /// The load-bearing invariant behind admitting our own zero-conf is that
    /// `ownUnconfirmedTxHashes` can only ever *rescue* a row, never add one.
    /// Every candidate here was returned by the provider as part of the
    /// address's current unspent set, so a parent that was dropped, evicted or
    /// never propagated contributes nothing to spend in the first place — its
    /// outputs simply are not in `rows`. The pending record answers "is this
    /// ours", not "does this exist"; the provider answers the second question.
    ///
    /// Two residual costs are accepted rather than fixed here. A parent
    /// evicted between selection and broadcast takes its child with it, which
    /// costs a rejected broadcast and no money — unlike a stranger's zero-conf,
    /// where the counterparty can double-spend deliberately. And a long enough
    /// chain of unconfirmed sends eventually hits the network's mempool
    /// ancestor limit and is refused until one of them confirms.
    ///
    /// Rows missing the fields needed to build an input are dropped rather
    /// than failing the whole set.
    ///
    /// - Parameter ownUnconfirmedTxHashes: hashes of transactions this device
    ///   broadcast for this vault on this chain that have not reached a
    ///   terminal state — see `ownUnconfirmedTxHashes(chain:vaultPubKeyECDSA:)`.
    ///   An empty set is the safe degradation: it collapses the predicate back
    ///   to confirmed-only.
    static func select(
        from rows: [Blockchair.BlockchairUtxo],
        dustThreshold: Int64,
        ownUnconfirmedTxHashes: Set<String>
    ) -> [UtxoInfo] {
        // Blockchair lower-cases transaction hashes and so does WalletCore's
        // `transactionID`, but the stored hash can also come back from a
        // broadcast proxy, so neither side's casing is guaranteed.
        let ownHashes = Set(ownUnconfirmedTxHashes.map { $0.lowercased() })

        return rows.compactMap { row -> UtxoInfo? in
            guard row.isSpendable != false,
                  let txHash = row.transactionHash, !txHash.isEmpty,
                  let value = row.value, let amount = Int64(exactly: value), amount >= dustThreshold,
                  let index = row.index, let vout = UInt32(exactly: index)
            else {
                return nil
            }

            // A row whose depth we could not establish is treated as
            // unconfirmed: absent evidence of a block is not evidence of one.
            let isConfirmed = (row.blockId ?? 0) > 0
            guard isConfirmed || ownHashes.contains(txHash.lowercased()) else {
                return nil
            }

            return UtxoInfo(hash: txHash, amount: amount, index: vout)
        }
    }

    /// The balance of exactly the set `select` admits, in the chain's smallest
    /// unit. Defined in terms of `select` rather than alongside it so the two
    /// cannot drift.
    ///
    /// `BigInt` because the sum is not bounded by the per-output type the
    /// values arrive in: an address holding enough of a high-supply,
    /// eight-decimal chain overflows `Int64` in arithmetic no wallet should
    /// ever trap on.
    static func balance(
        from rows: [Blockchair.BlockchairUtxo],
        dustThreshold: Int64,
        ownUnconfirmedTxHashes: Set<String>
    ) -> BigInt {
        select(
            from: rows,
            dustThreshold: dustThreshold,
            ownUnconfirmedTxHashes: ownUnconfirmedTxHashes
        )
        .reduce(BigInt(0)) { $0 + BigInt($1.amount) }
    }

    /// Snapshots the transaction hashes this device broadcast for `chain` and
    /// `vaultPubKeyECDSA` that have not reached a terminal state.
    ///
    /// Returns a value type by construction: `StoredPendingTransaction` is a
    /// SwiftData `@Model` that must never be touched off the main actor, while
    /// both callers of `select` run off it.
    ///
    /// Scoped to one vault as well as one chain. A pending transaction only
    /// vouches for the outputs of the wallet that signed it — another vault's
    /// zero-conf payment into this one is still someone else's, even when both
    /// vaults live on this device.
    static func ownUnconfirmedTxHashes(chain: Chain, vaultPubKeyECDSA: String?) async -> Set<String> {
        guard let vaultPubKeyECDSA, !vaultPubKeyECDSA.isEmpty else { return [] }
        return await MainActor.run {
            StoredPendingTransactionStorage.shared.unconfirmedTransactionHashes(
                chain: chain,
                vaultPubKeyECDSA: vaultPubKeyECDSA
            )
        }
    }
}
