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
    /// than failing the whole set — but, unlike the policy exclusions above,
    /// their count is logged, because there is no legitimate reason for one to
    /// exist. See `unusableRowCount(in:)`.
    ///
    /// - Parameter ownUnconfirmedTxHashes: hashes of transactions this device
    ///   broadcast for this vault on this chain that have not reached a
    ///   terminal state — see `ownUnconfirmedTxHashes(chain:vaultPubKeyECDSA:)`.
    ///   An empty set collapses the predicate back to confirmed-only, which is
    ///   the right answer when the wallet genuinely has nothing pending — but
    ///   never a substitute for a lookup that *failed*, which throws.
    static func select(
        from rows: [Blockchair.BlockchairUtxo],
        dustThreshold: Int64,
        ownUnconfirmedTxHashes: Set<String>
    ) -> [UtxoInfo] {
        // Blockchair lower-cases transaction hashes and so does WalletCore's
        // `transactionID`, but the stored hash can also come back from a
        // broadcast proxy, so neither side's casing is guaranteed.
        let ownHashes = Set(ownUnconfirmedTxHashes.map { $0.lowercased() })

        logUnusableRows(in: rows)

        return rows.compactMap { row -> UtxoInfo? in
            guard let outPoint = usableOutPoint(of: row) else { return nil }

            guard row.isSpendable != false, outPoint.amount >= dustThreshold else {
                return nil
            }

            // A row whose depth we could not establish is treated as
            // unconfirmed: absent evidence of a block is not evidence of one.
            let isConfirmed = (row.blockId ?? 0) > 0
            guard isConfirmed || ownHashes.contains(outPoint.hash.lowercased()) else {
                return nil
            }

            return UtxoInfo(hash: outPoint.hash, amount: outPoint.amount, index: outPoint.index)
        }
    }

    /// The three fields an input is built from, or `nil` when the row does not
    /// carry them.
    ///
    /// Separated from the policy filters above because the two failures mean
    /// opposite things. A row excluded for dust, for an explicit
    /// `is_spendable: false`, or for being a stranger's zero-conf is *working
    /// as designed* — that money is legitimately not spendable right now. A row
    /// that cannot even name an outpoint is a defect: either the provider
    /// changed its response shape or our decoding of it regressed, and because
    /// every field on `BlockchairUtxo` is optional such a row decodes cleanly
    /// and is then silently dropped, understating the displayed balance by
    /// whatever it held with nothing anywhere failing.
    private static func usableOutPoint(
        of row: Blockchair.BlockchairUtxo
    ) -> (hash: String, amount: Int64, index: UInt32)? {
        guard let hash = row.transactionHash, !hash.isEmpty,
              let value = row.value, let amount = Int64(exactly: value),
              let index = row.index, let vout = UInt32(exactly: index)
        else {
            return nil
        }
        return (hash, amount, vout)
    }

    /// Rows the provider returned that cannot identify an output at all.
    ///
    /// Exposed so the defect above is observable rather than inferred from a
    /// balance that quietly came out too low. A hard failure would be the wrong
    /// answer — `address.balance` legitimately exceeds the spendable sum on
    /// every address holding a stranger's zero-conf or a sub-dust output, so
    /// any threshold on that divergence would fire constantly — but the count
    /// of unusable rows has no legitimate non-zero value.
    static func unusableRowCount(in rows: [Blockchair.BlockchairUtxo]) -> Int {
        rows.reduce(0) { $0 + (usableOutPoint(of: $1) == nil ? 1 : 0) }
    }

    private static func logUnusableRows(in rows: [Blockchair.BlockchairUtxo]) {
        let unusable = unusableRowCount(in: rows)
        guard unusable > 0 else { return }
        Log.chain.service.error(
            "Dropped \(unusable) of \(rows.count) Blockchair UTXO rows with no usable transaction_hash/index/value — the balance understates this address by whatever they held"
        )
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
    static func ownUnconfirmedTxHashes(chain: Chain, vaultPubKeyECDSA: String?) async throws -> Set<String> {
        guard let vaultPubKeyECDSA, !vaultPubKeyECDSA.isEmpty else { return [] }
        return try await MainActor.run {
            try StoredPendingTransactionStorage.shared.unconfirmedTransactionHashes(
                chain: chain,
                vaultPubKeyECDSA: vaultPubKeyECDSA
            )
        }
    }
}
