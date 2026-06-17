//
//  VultPendingRequestReconciler.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "vult-pending-reconciler")

/// Recovers VULT unstake `requestId`s from our own `requestUnstake` tx receipts.
///
/// iOS has no `eth_getLogs`, so a pending request can't be enumerated from the
/// chain. Instead, this scans the vault's recorded Ethereum transaction history
/// for VULT requestUnstake txs, fetches each receipt (`eth_getTransactionReceipt`,
/// already used for tx status), and decodes the `UnstakeRequested` log to capture
/// `requestId` + `maturity`. New requests are persisted as pending redemptions.
///
/// Already-scanned tx hashes are remembered per vault so a refresh doesn't re-hit
/// the RPC for the same receipts. Fail closed: a real pending request is captured
/// the first time its receipt resolves; a transient read failure is retried on the
/// next refresh (the hash is only marked scanned once a receipt is seen).
struct VultPendingRequestReconciler {
    private let reads: VultReadService
    private let provider: VultYieldProvider
    private let history: TransactionHistoryStorage

    /// How far back to scan history rows on each reconcile.
    private let maxRowsToScan = 50

    init(
        reads: VultReadService = .shared,
        provider: VultYieldProvider = VultYieldProvider(),
        history: TransactionHistoryStorage = .shared
    ) {
        self.reads = reads
        self.provider = provider
        self.history = history
    }

    /// Scans recent Ethereum history for un-captured VULT unstake requests and
    /// persists any found. Returns the count of newly captured requests.
    @discardableResult
    @MainActor
    func reconcile(vault: Vault) async -> Int {
        let pubKey = vault.pubKeyECDSA
        guard !pubKey.isEmpty else { return 0 }

        let rows: [TransactionHistoryData]
        do {
            rows = try history.fetchByChain(pubKeyECDSA: pubKey, chainRawValue: VultConstants.chain.rawValue)
        } catch {
            logger.warning("VULT reconcile history fetch failed: \(error.localizedDescription)")
            return 0
        }

        var scanned = scannedHashes(for: pubKey)
        let candidates = rows
            .prefix(maxRowsToScan)
            .filter { isUnstakeCandidate($0) && !scanned.contains($0.txHash.lowercased()) }

        guard !candidates.isEmpty else { return 0 }

        let existingIDs = Set(provider.persistedRedemptionIDs(vault: vault))
        var captured = 0

        for row in candidates {
            guard let log = await reads.fetchUnstakeRequestedLog(txHash: row.txHash) else {
                // Receipt not available yet (still pending) — leave the hash
                // unscanned so a later refresh retries it.
                continue
            }
            // Receipt resolved: don't re-scan this hash.
            scanned.insert(row.txHash.lowercased())

            let id = log.requestId.description
            guard !existingIDs.contains(id) else { continue }

            let redemption = YieldRedemption(
                id: id,
                amount: VultYieldProvider.humanAmount(log.amount),
                requestedAt: row.createdAt,
                claimableAt: VultYieldProvider.maturityDate(log.maturity),
                status: .pending
            )
            provider.persistCapturedRequest(redemption, vault: vault)
            captured += 1
            logger.info("Captured VULT requestId \(id) from \(row.txHash)")
        }

        setScannedHashes(scanned, for: pubKey)
        return captured
    }

    /// A history row that could be a VULT requestUnstake: a successful Ethereum
    /// send whose display asset is VULT. The receipt fetch + log match is the real
    /// filter (false positives just cost one RPC read), so this stays permissive
    /// to avoid ever missing a real request.
    private func isUnstakeCandidate(_ row: TransactionHistoryData) -> Bool {
        row.type == .send
            && row.coinTicker.uppercased() == VultConstants.underlyingTicker
            && row.status != .error
    }

    // MARK: - Scanned-hash bookkeeping (per vault, RPC-frugal)

    private func scannedKey(for pubKey: String) -> String { "vultScannedReceipts_\(pubKey)" }

    private func scannedHashes(for pubKey: String) -> Set<String> {
        let stored = UserDefaults.standard.stringArray(forKey: scannedKey(for: pubKey)) ?? []
        return Set(stored)
    }

    private func setScannedHashes(_ hashes: Set<String>, for pubKey: String) {
        // Cap the stored set so it can't grow unbounded across a vault's lifetime.
        let capped = Array(hashes.prefix(500))
        UserDefaults.standard.set(capped, forKey: scannedKey(for: pubKey))
    }
}
