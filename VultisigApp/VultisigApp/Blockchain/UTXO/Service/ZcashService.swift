//
//  ZcashService.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "zcash-service")

/// Resolves the active ZIP-243 consensus branch id WalletCore needs on the
/// Zcash transaction plan. The branch id changes at every Zcash network
/// upgrade, so a compiled-in constant goes stale and makes every ZEC send /
/// SwapKit swap sign with the wrong id and get rejected chain-wide until the
/// app ships a new release. Resolving it from the node at send time keeps
/// signing correct across upgrades with no code change.
actor ZcashService {

    static let shared = ZcashService()

    private let rpc = RpcService(Endpoint.zcashServiceRpc)
    private var cachedBranchId: String?
    private var cachedAt: Date?
    private var inFlight: Task<String?, Never>?

    /// One hour: the branch id only changes at a network upgrade, so a single
    /// keysign's preimage-hash and final-compile passes (and repeated sends)
    /// all read the same cached value, keeping the digest stable across them.
    private let cacheTTL: TimeInterval = 60 * 60

    /// Resolves the active ZIP-243 consensus branch id for the next block, as
    /// the little-endian hex string WalletCore expects on the plan (e.g.
    /// `30f33754`). The node reports it big-endian (`consensus.nextblock`, e.g.
    /// `5437f330`); this reverses the four bytes.
    ///
    /// Returns `nil` when the RPC is unreachable or the response is malformed;
    /// signing then refuses to proceed (there is no compiled-in fallback, since
    /// a stale branch id yields a network-rejected tx). The branch id is a
    /// network-global fact, so every device that resolves it at signing time
    /// agrees, keeping MPC co-signers in sync.
    func getConsensusBranchIdHex() async -> String? {
        if let cached = freshCachedBranchId() {
            return cached
        }
        // Dedupe concurrent co-sign rounds so they issue a single network call.
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await fetchBranchId() }
        inFlight = task
        let fetched = await task.value
        inFlight = nil
        // Only cache successful fetches so a transient RPC failure doesn't pin
        // the wallet to that failure for a whole hour.
        if let fetched {
            cachedBranchId = fetched
            cachedAt = Date()
        }
        return fetched
    }

    private func freshCachedBranchId() -> String? {
        guard let cachedBranchId, let cachedAt,
              Date().timeIntervalSince(cachedAt) < cacheTTL else {
            return nil
        }
        return cachedBranchId
    }

    private func fetchBranchId() async -> String? {
        do {
            let nextBlock: String? = try await rpc.sendRPCRequest(
                method: "getblockchaininfo",
                params: []
            ) { result in
                guard let dict = result as? [String: Any],
                      let consensus = dict["consensus"] as? [String: Any] else {
                    return nil
                }
                return consensus["nextblock"] as? String
            }
            guard let nextBlock, !nextBlock.isEmpty else {
                logger.warning("Zcash getblockchaininfo returned no consensus.nextblock branch id")
                return nil
            }
            return Self.reverseHexBytes(nextBlock)
        } catch {
            logger.error("Failed to fetch Zcash consensus branch id: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reverses the byte order of a 4-byte (8 hex char) big-endian branch id
    /// into the little-endian form WalletCore reads from the plan. Returns
    /// `nil` for any input that is not exactly four hex bytes so a malformed
    /// RPC response makes signing refuse rather than use a bad sighash.
    static func reverseHexBytes(_ hex: String) -> String? {
        guard hex.count == 8, hex.allSatisfy(\.isHexDigit) else {
            logger.warning("Zcash branch id '\(hex)' is not a 4-byte hex value")
            return nil
        }
        let chars = Array(hex)
        let bytes = stride(from: 0, to: chars.count, by: 2).map { String(chars[$0...$0 + 1]) }
        return bytes.reversed().joined().lowercased()
    }
}
