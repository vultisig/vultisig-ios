//
//  LimitOrderStorageService.swift
//  VultisigApp
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted on the main actor after `LimitOrderStorageService.persist` /
    /// `updateStatus` saves changes to SwiftData. Phase 2's Open-Orders surface
    /// in TX History should observe this to refresh — `@ObservedObject` does
    /// not propagate in-place mutations of nested `@Model` arrays back to the
    /// parent vault.
    static let limitOrdersDidChange = Notification.Name("com.vultisig.app.limitOrdersDidChange")
}

enum LimitOrderStorageError: Error, Equatable {
    case duplicate(id: String)
    case notFound(id: String)
    /// A record was handed to `persist` before its inbound TX hash was spliced
    /// in. The unique id is `inboundTxHash + pubKeyECDSA`; persisting with an
    /// empty hash would make every pre-broadcast order collide on `"_pubkey"`,
    /// silently dropping all but the first. Fail loud instead of corrupting the
    /// open-orders table.
    case emptyInboundTxHash
}

struct LimitOrderStorageService {

    /// Persists a freshly-placed limit order. Idempotency is the caller's
    /// responsibility — the inbound TX hash is what makes each order unique,
    /// and the keysign flow only invokes this on broadcast success.
    @discardableResult
    @MainActor
    func persist(_ record: LimitOrderRecord, for vault: Vault) throws -> LimitOrder {
        guard !record.inboundTxHash.isEmpty else {
            throw LimitOrderStorageError.emptyInboundTxHash
        }
        let id = makeId(inboundTxHash: record.inboundTxHash, vault: vault)
        if vault.limitOrders.contains(where: { $0.id == id }) {
            throw LimitOrderStorageError.duplicate(id: id)
        }
        let model = LimitOrder(
            id: id,
            inboundTxHash: record.inboundTxHash,
            sourceAsset: record.sourceAsset,
            sourceAmount: record.sourceAmount,
            sourceDecimals: record.sourceDecimals,
            targetAsset: record.targetAsset,
            destAddress: record.destAddress,
            targetPrice: record.targetPrice,
            expiryBlocks: record.expiryBlocks,
            createdAt: record.createdAt,
            status: record.status,
            minOutputOverride: record.minOutputOverride,
            sourceAmount1e8: record.sourceAmount1e8,
            tradeTarget: record.tradeTarget,
            sourceAssetFull: record.sourceAssetFull,
            targetAssetFull: record.targetAssetFull,
            sourceChainRawValue: record.sourceChainRawValue,
            vault: vault
        )
        Storage.shared.modelContext.insert(model)
        try saveAndNotify()
        return model
    }

    /// Returns this vault's orders sorted newest-first.
    @MainActor
    func fetchAll(for vault: Vault) -> [LimitOrder] {
        vault.limitOrders.sorted(by: { $0.createdAt > $1.createdAt })
    }

    /// This vault's orders as Sendable snapshots, keyed by inbound tx hash
    /// (UPPERCASED).
    ///
    /// Uppercased because this map is joined against `TransactionHistoryData.txHash`,
    /// and hex case is not semantic — the casing a row was broadcast under need
    /// not match the casing anything else stores. A case-sensitive join here
    /// would silently miss, and the order card would fall back to showing no
    /// target price at all rather than failing visibly.
    @MainActor
    func fetchDetailsByTxHash(for vault: Vault) -> [String: LimitOrderDetails] {
        Dictionary(
            vault.limitOrders.map { ($0.inboundTxHash.uppercased(), $0.details) },
            // An inbound hash identifies one order, so a collision means two
            // rows claim the same order. Keep the newest — it observed last.
            uniquingKeysWith: { first, second in first.createdAt >= second.createdAt ? first : second }
        )
    }

    /// In-place status update. Throws if the given id isn't on this vault.
    @MainActor
    func updateStatus(of orderId: String, to status: LimitOrderStatus, in vault: Vault) throws {
        guard let order = vault.limitOrders.first(where: { $0.id == orderId }) else {
            throw LimitOrderStorageError.notFound(id: orderId)
        }
        order.statusRawValue = status.rawValue
        try saveAndNotify()
    }

    /// The cancel transaction recorded against this order, if any.
    ///
    /// Read by the tracker so it can re-verify that transaction on-chain and
    /// withdraw the record if it turns out to have failed.
    @MainActor
    func pendingCancelBroadcast(of orderId: String, in vault: Vault) -> String? {
        vault.limitOrders.first(where: { $0.id == orderId })?.cancelBroadcastHash
    }

    /// Withdraw a cancel record whose transaction did NOT succeed on-chain.
    ///
    /// ⚠️ The self-heal for the failure the rehearsal found. A cancel can be
    /// included in a block and still be REFUSED by the handler — THORChain
    /// answered `could not find matching limit swap` with a non-zero code — and
    /// a record kept on that basis is doubly wrong: it disables the Cancel
    /// button for good on an order that is still resting and still cancellable,
    /// and it leaves a later closure ready to be labelled "Cancelled" when
    /// nothing was cancelled.
    ///
    /// Reverts the ONE label the record produced: `.cancelling`, which says
    /// nothing except that our transaction landed, and which goes back to
    /// `.pending` — re-enabling the Cancel button, the point of the self-heal.
    ///
    /// ⚠️ **A terminal label is left alone, including `.cancelled`.** It used to
    /// be reverted to `.refunded` on the reasoning that `.cancelled` could only
    /// ever have come from this record. That is no longer true: the tracker
    /// reads THORChain's own `"limit swap cancelled"` off the refund action
    /// Midgard indexes, and writes `.cancelled` on that alone. Rewriting it here
    /// would replace the chain's account of the order with our bookkeeping about
    /// a transaction — and our transaction failing does not un-cancel an order
    /// that something else cancelled.
    ///
    /// This is reachable only for an order still RESTING in the queue anyway
    /// (`verifyPendingCancel` is the sole caller and re-checks nothing else), so
    /// the terminal arms are a guard rather than a path.
    ///
    /// - Parameter expecting: compare-and-set. The caller looked the hash up,
    ///   went to the network to check it, and is acting on an answer that is by
    ///   then several seconds old; a different hash stored in the meantime is a
    ///   different cancel, and withdrawing IT on the strength of the old one's
    ///   failure would unblock a cancel that is genuinely in flight. Any
    ///   mismatch is a no-op — the newer record's own verification will settle
    ///   it.
    @MainActor
    func clearCancelBroadcast(of orderId: String, expecting txHash: String, in vault: Vault) throws {
        guard let order = vault.limitOrders.first(where: { $0.id == orderId }) else {
            throw LimitOrderStorageError.notFound(id: orderId)
        }
        guard order.cancelBroadcastHash == txHash else { return }
        order.cancelBroadcastHash = nil
        // The confirmation flag belongs to that hash; a withdrawn cancel is no
        // longer confirmed, and a later cancel starts from unconfirmed.
        order.cancelConfirmedOnChain = nil
        switch order.status {
        case .cancelling:
            order.statusRawValue = LimitOrderStatus.pending.rawValue
        case .pending, .filled, .refunded, .expired, .cancelled:
            break
        }
        try saveAndNotify()
    }

    /// Marks the recorded cancel as CONFIRMED on-chain, then reconciles.
    ///
    /// Called once the cancel transaction is verified — `.succeeded` on the
    /// THORChain route, `.delivered` on an L1 route — by the done-screen poller or
    /// the tracker's re-check. Confirmation is what unlocks the no-reason
    /// `.refunded → .cancelled` fallback in `reconcile`: until it lands, a
    /// merely-broadcast cancel shows `.cancelling` but can never produce a
    /// terminal `.cancelled` from local evidence.
    ///
    /// Compare-and-set on the hash: a cancel recorded since is a different
    /// transaction this confirmation says nothing about. Re-reconciles so a
    /// `.refunded` closure already observed while the cancel was unconfirmed is
    /// promoted the moment confirmation arrives (still subject to the TTL rule).
    @MainActor
    func confirmCancelBroadcast(of orderId: String, txHash: String, in vault: Vault) throws {
        guard let order = vault.limitOrders.first(where: { $0.id == orderId }) else {
            throw LimitOrderStorageError.notFound(id: orderId)
        }
        guard order.cancelBroadcastHash == txHash else { return }
        order.cancelConfirmedOnChain = true
        order.statusRawValue = Self.reconcile(observed: order.status, with: order).rawValue
        try saveAndNotify()
    }

    /// Records the cancel transaction against this order and moves a resting
    /// order into `.cancelling`.
    ///
    /// ⚠️ **Called on a confirmed BROADCAST — a non-empty hash — not on an
    /// on-chain result.** Entering `.cancelling` here, block-independently, is
    /// what makes the in-flight state observable at all; gating it on the chain's
    /// answer left it unseen for a fast cancel (see `LimitOrderCancelPoller`).
    /// This is safe only because the hash no longer labels the CLOSURE: the
    /// terminal `.cancelled`/`.expired`/`.refunded` label comes from THORChain's
    /// own reason (via `reconcile` and the tracker), so an optimistic hash yields
    /// the NON-terminal `.cancelling` and never a false terminal "Cancelled". A
    /// cancel the chain later refuses has its record withdrawn by
    /// `clearCancelBroadcast`, driven from either the poller or the tracker.
    ///
    /// Compare-and-set on `.pending`: an order that has already gone terminal is
    /// left exactly as it is. The window is real — an order can fill or expire
    /// between the user tapping Cancel and the ceremony completing — and a blind
    /// write would resurrect a filled order into a cancelled one, telling the
    /// user their funds went back when they were actually swapped.
    ///
    /// Deliberately does NOT set `.cancelled`. See `LimitOrder.cancelBroadcastHash`:
    /// a cancel that matches nothing is accepted by the chain and does nothing,
    /// so the order stays resting until the queue confirms it actually closed.
    /// It does move a still-resting order to `.cancelling` — a NON-terminal
    /// state that says our transaction went out and says nothing about the order.
    /// `.refunded` is accepted as well as `.pending`: the tracker can observe the
    /// closure BEFORE this runs — the done screen renders a moment after
    /// broadcast, but a force-quit or a backgrounded app can let a poll land
    /// first — and rejecting `.refunded` would drop the hash on the floor, so a
    /// cancel that CONFIRMS moments later could never promote the already-observed
    /// closure. Storing the hash keeps that door open; the promotion itself still
    /// waits for `confirmCancelBroadcast`, so recording onto a `.refunded` order
    /// leaves it `.refunded` for now, never optimistically `.cancelled`.
    ///
    /// `.cancelling` is accepted too, purely so a re-record of the same
    /// transaction is a no-op rather than a silently dropped write.
    ///
    /// `.filled`, `.expired` and `.cancelled` are still refused: those are
    /// outcomes the cancel demonstrably did not cause.
    @MainActor
    func recordCancelBroadcast(of orderId: String, txHash: String, in vault: Vault) throws {
        guard let order = vault.limitOrders.first(where: { $0.id == orderId }) else {
            throw LimitOrderStorageError.notFound(id: orderId)
        }
        guard order.status == .pending || order.status == .refunded || order.status == .cancelling else { return }
        if order.cancelBroadcastHash != txHash {
            // A newly-recorded broadcast is a DIFFERENT, not-yet-confirmed cancel.
            // Confirmation belongs to a specific hash (see `confirmCancelBroadcast`),
            // so a prior hash's confirmation must not carry onto this one — else a
            // merely-broadcast replacement could claim a no-reason refund the old
            // cancel earned. Cleared here; re-recording the SAME hash keeps it.
            order.cancelConfirmedOnChain = nil
        }
        order.cancelBroadcastHash = txHash
        // Re-run reconciliation against what is already recorded. A `.pending`
        // order becomes `.cancelling`; a `.refunded` closure already observed
        // stays `.refunded` — the broadcast is not yet confirmed, and only a
        // CONFIRMED cancel may claim a no-reason refund (see `reconcile` and
        // `confirmCancelBroadcast`).
        order.statusRawValue = Self.reconcile(observed: order.status, with: order).rawValue
        try saveAndNotify()
    }

    /// Records an on-chain observation of an order: its status and its fill
    /// split, in one save.
    ///
    /// Status and amounts are written together on purpose. They are read
    /// together — "Expired · 40% filled" is one statement — and persisting them
    /// separately would leave a window where the row claims a status its
    /// amounts contradict.
    ///
    /// A `nil` amount means "not observed this poll" and LEAVES the stored value
    /// alone; it never overwrites a known split with unknown. That matters at
    /// exactly the moment it's hardest to re-fetch: an order goes terminal by
    /// disappearing from the queue, and the last good observation is all we will
    /// ever have.
    ///
    /// `timeToExpiryBlocks` follows the same rule and is stamped with
    /// `observedAt` when present — the pair is what makes the expiry chip a live
    /// countdown rather than a stale number.
    ///
    /// - Returns: the status actually STORED, which is `reconcile`'s verdict on
    ///   the observation, not the observation itself. The caller mirrors this
    ///   onto the tx-history row: returning the raw observation instead would
    ///   leave the row saying "pending" for an order the authoritative table
    ///   calls `.cancelling`, and the two tables disagreeing is the failure this
    ///   mirror exists to avoid.
    @discardableResult
    @MainActor
    func recordObservation(
        of orderId: String,
        status: LimitOrderStatus,
        depositAmount: String? = nil,
        filledInAmount: String? = nil,
        filledOutAmount: String? = nil,
        observedTradeTarget: String? = nil,
        observedSourceAsset: String? = nil,
        observedTargetAsset: String? = nil,
        timeToExpiryBlocks: Int? = nil,
        observedAt: Date = Date(),
        in vault: Vault
    ) throws -> LimitOrderStatus {
        guard let order = vault.limitOrders.first(where: { $0.id == orderId }) else {
            throw LimitOrderStorageError.notFound(id: orderId)
        }
        let effective = Self.reconcile(observed: status, with: order)
        order.statusRawValue = effective.rawValue
        if let depositAmount { order.depositAmount = depositAmount }
        if let observedTradeTarget { order.observedTradeTarget = observedTradeTarget }
        if let observedSourceAsset { order.observedSourceAsset = observedSourceAsset }
        if let observedTargetAsset { order.observedTargetAsset = observedTargetAsset }
        if let filledInAmount { order.filledInAmount = filledInAmount }
        if let filledOutAmount { order.filledOutAmount = filledOutAmount }
        if let timeToExpiryBlocks {
            order.timeToExpiryBlocks = timeToExpiryBlocks
            // Stamped together — a countdown without its anchor is unusable, so
            // the two must never be written apart.
            order.expiryObservedAt = observedAt
        }
        try saveAndNotify()
        return effective
    }

    /// Reconcile an observed outcome against what this device knows it did.
    ///
    /// ⚠️ **This is now a FALLBACK, not the rule.** THORChain's own reason for
    /// closing an order reaches us through Midgard's refund action, so a
    /// cancellation normally arrives here already labelled `.cancelled` and
    /// passes straight through — including one performed on another device or in
    /// another wallet, which no amount of local bookkeeping could ever have
    /// attributed. What is left for this function is the two cases the chain
    /// does not answer:
    ///
    /// - a still-RESTING order with a confirmed cancel against it, which is
    ///   `.cancelling`. Not an outcome at all: it is our own transaction made
    ///   visible while the order carries on resting, and there is no chain
    ///   signal for it because nothing has happened to the order yet.
    /// - a `.refunded` closure carrying no reason we recognise — a missing
    ///   `metadata.refund.reason`, or a wording THORChain has changed. Then the
    ///   old local evidence is the only evidence there is.
    ///
    /// Narrow on purpose:
    /// - only `.refunded` is reinterpreted as an OUTCOME. A `.filled`
    ///   observation stands, and must: an order that filled before the cancel
    ///   landed genuinely filled, and relabelling that as cancelled would
    ///   misreport where the funds went.
    /// - `.cancelled` and `.expired` stand too — those came from the chain, and
    ///   a local record has nothing to add to them.
    /// - only when a cancel was actually broadcast for THIS order.
    /// - **and only if the order did not simply run out of time.**
    ///
    /// ⚠️ That last guard is what stops the fallback becoming a delayed version
    /// of the optimistic write it replaced. A cancel that addressed the wrong
    /// ratio bucket does nothing; hours later the order expires on its own and
    /// leaves the queue. Without the TTL check, that closure would be credited
    /// to the cancel and reported as a successful cancellation — telling the
    /// user their cancel worked when it silently failed and the order ran to
    /// expiry. An order that reached a terminal state on its own reached it on
    /// its own, and an outstanding cancel intent does not get to claim credit.
    ///
    /// The cancel is credited ONLY when it was CONFIRMED on-chain AND the order
    /// provably could not have expired on its own — its TTL still has not elapsed
    /// at the moment we observe the closure. A merely-broadcast cancel, or a
    /// closure at/after the TTL, stays `.refunded`. Confirmation is a distinct
    /// requirement because `.cancelling` is now entered on BROADCAST, before the
    /// chain's verdict; the terminal promotion must not be, or a cancel the chain
    /// refuses could relabel an unrelated refund "Cancelled".
    ///
    /// A closure is observed somewhere in the window between the last time we
    /// saw the order resting and the poll that found it gone. With no reason
    /// from the chain, and the TTL end falling inside that window, expiry and
    /// cancellation are indistinguishable from here — the order could have
    /// expired a minute before our cancel landed, or the cancel could have
    /// closed it a minute before the TTL. `.refunded` is precisely what that
    /// case is defined to mean: *"the funds came back, the observable fact"*.
    ///
    /// Pure and `static` so the reinterpretation is unit-testable without
    /// SwiftData.
    @MainActor
    static func reconcile(
        observed: LimitOrderStatus,
        with order: LimitOrder,
        now: Date = Date()
    ) -> LimitOrderStatus {
        guard order.cancelBroadcastHash != nil else { return observed }
        switch observed {
        case .pending:
            // Still in the queue, with a cancel BROADCAST against it. The user
            // gets an acknowledgement the instant it goes out; the order keeps
            // resting. Deliberately on the broadcast alone — this is the
            // non-terminal, non-success state the whole feature hangs on being
            // visible, and it makes no claim the chain has to have confirmed.
            return .cancelling
        case .refunded:
            // ⚠️ The terminal fallback, and the one place the cancel hash pulls
            // on a TERMINAL label. It fires only when the cancel was CONFIRMED
            // on-chain — never on a bare broadcast. Entry into `.cancelling` is
            // optimistic (broadcast); this promotion is not, because a broadcast
            // the chain later refuses must never turn an unrelated refund into a
            // false "Cancelled". That is exactly the safety the hash carried by
            // itself back when it was only ever written after confirmation.
            //
            // A cancel THORChain itself reports (`limit swap cancelled`) does not
            // reach here at all — it arrives as `.cancelled` and passes straight
            // through the case below, confirmed or not, because that is the
            // chain's own account and needs no local corroboration.
            let confirmed = order.cancelConfirmedOnChain == true
            return confirmed && closedBeforeExpiryWasPossible(order, now: now) ? .cancelled : .refunded
        case .cancelling, .filled, .expired, .cancelled:
            return observed
        }
    }

    /// True when the order's TTL demonstrably had NOT elapsed at `now`, so the
    /// closure cannot be an expiry.
    ///
    /// Prefers the anchored countdown the tracker persists
    /// (`timeToExpiryBlocks` + `expiryObservedAt`). Falls back to the nominal
    /// `createdAt + expiryBlocks × 6s` when the order was never polled while
    /// resting. Both are approximations, and both are used the same way: only
    /// to rule expiry OUT, never to assert it. An approximation that says "the
    /// deadline is still comfortably ahead" is trustworthy in a way that one
    /// saying "the deadline has just passed, therefore it expired" is not —
    /// `createdAt` predates queue insertion and 6s is an average, so the error
    /// sits exactly at the boundary this only ever reads far from.
    @MainActor
    private static func closedBeforeExpiryWasPossible(_ order: LimitOrder, now: Date) -> Bool {
        if let expiry = order.expiry {
            return !expiry.hasElapsed(now: now)
        }
        let nominalLifetime = TimeInterval(order.expiryBlocks) * LimitOrderExpiry.secondsPerBlock
        return now < order.createdAt.addingTimeInterval(nominalLifetime)
    }

    /// Convenience for callers that hold a vault's public key rather than the
    /// `@Model` — the tx-history viewmodel is keyed by `pubKeyECDSA`.
    ///
    /// Returns `[:]` when the vault can't be resolved. Unlike the write path,
    /// a read that comes up empty is not dangerous: the order cards simply fall
    /// back to what the row itself knows, rather than showing something wrong.
    @MainActor
    func fetchDetailsByTxHash(pubKeyECDSA: String) -> [String: LimitOrderDetails] {
        guard let vault = try? Self.vault(pubKeyECDSA: pubKeyECDSA) else { return [:] }
        return fetchDetailsByTxHash(for: vault)
    }

    /// A fetch failure propagates rather than collapsing into "no such vault":
    /// callers that WRITE must be able to tell the two apart, because only one
    /// of them means it is safe to stop retrying.
    @MainActor
    static func vault(pubKeyECDSA: String) throws -> Vault? {
        guard let modelContext = Storage.shared.modelContext else {
            throw LimitOrderObservingError.vaultUnavailable(pubKeyECDSA: pubKeyECDSA)
        }
        let descriptor = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == pubKeyECDSA })
        return try modelContext.fetch(descriptor).first
    }

    @MainActor
    private func makeId(inboundTxHash: String, vault: Vault) -> String {
        "\(inboundTxHash)_\(vault.pubKeyECDSA)"
    }
}

private extension LimitOrderStorageService {
    @MainActor
    func saveAndNotify() throws {
        try Storage.shared.save()
        NotificationCenter.default.post(name: .limitOrdersDidChange, object: nil)
    }
}
