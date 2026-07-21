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
    /// Reverts the labels the record produced along with the hash. Both
    /// `.cancelling` and `.cancelled` are derived from it and from nothing else
    /// (see `reconcile`), so a record withdrawn takes its conclusions with it:
    /// a still-resting order goes back to `.pending` — which re-enables its
    /// Cancel button, the point of the self-heal — and a closed one back to
    /// `.refunded`, the observable fact the tracker would have written on its
    /// own.
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
        switch order.status {
        case .cancelling:
            order.statusRawValue = LimitOrderStatus.pending.rawValue
        case .cancelled:
            order.statusRawValue = LimitOrderStatus.refunded.rawValue
        case .pending, .filled, .refunded, .expired:
            break
        }
        try saveAndNotify()
    }

    /// Records that a cancel transaction SUCCEEDED on-chain for this order.
    ///
    /// ⚠️ **Called on a confirmed-successful transaction, never on a broadcast.**
    /// A hash proves only that bytes were accepted for inclusion. The 2026-07-21
    /// rehearsal produced a hash, landed in a block, and was refused by the
    /// handler — recording that would have disabled the button on an order that
    /// was still resting, and pre-labelled its eventual closure "Cancelled".
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
    /// state that says our transaction landed and says nothing about the order.
    /// `.refunded` is accepted as well as `.pending`, and reconciled on the spot.
    /// The tracker can observe the cancel-induced closure BEFORE this runs — the
    /// done screen renders a moment after broadcast, but a force-quit or a
    /// backgrounded app can let a poll land first. Rejecting `.refunded` would
    /// then drop the hash on the floor and leave a successfully cancelled order
    /// reading "Refunded" forever, with nothing left to correct it.
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
        order.cancelBroadcastHash = txHash
        // Re-run reconciliation against what is already recorded. A `.pending`
        // order is unchanged by this; an already-observed `.refunded` closure is
        // promoted now that we know a cancel caused it (still subject to the
        // TTL precedence in `reconcile`).
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
    /// The queue never says WHY an order closed, so the tracker can only report
    /// what it saw: the funds came back, i.e. `.refunded`. But if we broadcast a
    /// cancel for this order, a refund IS that cancel settling — and `EventLimitSwapClose`,
    /// which carries the authoritative reason, reaches no REST route and no
    /// Midgard index, so this local knowledge is the ONLY way the two are ever
    /// told apart. Without it a user who cancelled would be shown "Refunded".
    ///
    /// Narrow on purpose:
    /// - only `.refunded` is reinterpreted as an OUTCOME. A `.filled`
    ///   observation stands, and must: an order that filled before the cancel
    ///   landed genuinely filled, and relabelling that as cancelled would
    ///   misreport where the funds went.
    /// - a `.pending` observation — the order is still in the queue — becomes
    ///   `.cancelling`, which is not an outcome at all: it is the confirmed
    ///   cancel TRANSACTION made visible while the order carries on resting.
    /// - only when a cancel was actually broadcast for THIS order.
    /// - **and only if the order did not simply run out of time.**
    ///
    /// ⚠️ That last guard is what stops this becoming a delayed version of the
    /// optimistic write it replaced. A cancel that addressed the wrong ratio
    /// bucket does nothing; hours later the order expires on its own and leaves
    /// the queue. Without the TTL check, that closure would be credited to the
    /// cancel and reported as a successful cancellation — telling the user their
    /// cancel worked when it silently failed and the order ran to expiry. An
    /// order that reached a terminal state on its own reached it on its own, and
    /// an outstanding cancel intent does not get to claim credit. Same reasoning
    /// as `.filled` above.
    ///
    /// The cancel is credited ONLY when the order provably could not have
    /// expired on its own — i.e. its TTL still has not elapsed at the moment we
    /// observe the closure. Anything else stays `.refunded`.
    ///
    /// The reasoning is about what the evidence can actually support. A closure
    /// is observed somewhere in the window between the last time we saw the
    /// order resting and the poll that found it gone. If the TTL end falls
    /// inside that window, expiry and cancellation are **indistinguishable** —
    /// the order could have expired a minute before our cancel landed, or the
    /// cancel could have closed it a minute before the TTL. Nothing reachable
    /// from a client separates them: `EventLimitSwapClose` carries the reason
    /// and reaches no REST route and no Midgard index.
    ///
    /// So the ambiguous case reports `.refunded`, which is precisely what that
    /// case is defined to mean — *"the funds came back, the observable fact"*,
    /// explicitly distinct from `.expired`, which `LimitOrderStatus` documents
    /// as "a claim about WHY". Claiming `.expired` here would be the same
    /// overclaim as claiming `.cancelled`, pointed the other way; the honest
    /// answer is the one that asserts only what was seen.
    ///
    /// The cost is that a genuine cancellation observed long after the fact —
    /// the app reopened days later — reads "Refunded" rather than "Cancelled".
    /// That is an under-claim about the cause of an identical funds movement,
    /// and it is the right direction to be wrong in: it never tells a user an
    /// action succeeded when it may have silently failed.
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
            // Still in the queue, with a confirmed cancel transaction against
            // it. The user gets an acknowledgement; the order keeps resting.
            return .cancelling
        case .refunded:
            return closedBeforeExpiryWasPossible(order, now: now) ? .cancelled : .refunded
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
