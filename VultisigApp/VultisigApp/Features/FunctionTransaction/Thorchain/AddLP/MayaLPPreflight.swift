//
//  MayaLPPreflight.swift
//  VultisigApp
//
//  Validates MayaChain network state before either side of an add-liquidity
//  inbound is signed. mayanode would accept the inbound, refund it and keep the
//  gas, so each case mirrors a check its add-liquidity handler runs.
//

import Foundation

enum MayaLPPreflightBlock: Equatable {
    /// Adds are paused by mimir `PAUSELP` (global) or `PAUSELP<CHAIN>`.
    case lpPaused(pool: String)
    /// The pool's asset chain is halted, or its inbound reports LP actions paused.
    case chainHalted(chainPrefix: String)
    /// The pool takes no adds at all (typically `Suspended`).
    case poolNotAvailable(pool: String)
    /// A `Staged` pool opens only to adds naming the other side's address.
    case stagedPoolRequiresPairedAdd(pool: String)

    var message: String {
        switch self {
        case .lpPaused(let pool):
            return String(format: "mayaLpPaused".localized, pool)
        case .chainHalted(let chainPrefix):
            return String(format: "mayaLpHaltedChain".localized, chainPrefix)
        case .poolNotAvailable(let pool):
            return String(format: "mayaLpPoolNotAvailable".localized, pool)
        case .stagedPoolRequiresPairedAdd(let pool):
            return String(format: "mayaLpStagedUnpaired".localized, pool)
        }
    }
}

enum MayaLPPreflight {

    private static let pauseKey = "PAUSELP"
    private static let mayaPrefix = "MAYA"

    /// The first reason this add would be refunded, or nil. Every signal is
    /// optional and fails open, so a transient node hiccup does not block a
    /// healthy deposit.
    static func evaluate(
        pool: String,
        isPairedAdd: Bool,
        mimir: [String: Int64]?,
        height: Int64?,
        inbound: InboundAddress?,
        poolStatus: String?
    ) -> MayaLPPreflightBlock? {
        let chainPrefix = pool.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map { String($0).uppercased() } ?? ""

        if let mimir,
           isActive(mimir[pauseKey], at: height) || isActive(mimir[pauseKey + chainPrefix], at: height) {
            return .lpPaused(pool: pool)
        }

        if chainPrefix != mayaPrefix, let inbound,
           inbound.halted || (inbound.chain_lp_actions_paused ?? false) {
            return .chainHalted(chainPrefix: chainPrefix)
        }

        guard let status = poolStatus else { return nil }
        if status.caseInsensitiveCompare("Available") == .orderedSame { return nil }
        if status.caseInsensitiveCompare("Staged") == .orderedSame {
            return isPairedAdd ? nil : .stagedPoolRequiresPairedAdd(pool: pool)
        }
        return .poolNotAvailable(pool: pool)
    }

    /// mayanode's `value > 0 && value < height`: the key pauses adds only once
    /// the chain is past it. An unknown height counts any set key as active, so
    /// a failed height read cannot let a configured pause through.
    private static func isActive(_ value: Int64?, at height: Int64?) -> Bool {
        guard let value, value > 0 else { return false }
        guard let height else { return true }
        return value < height
    }

    /// Reads the live signals and evaluates them.
    static func live(pool: String, isPairedAdd: Bool) async -> MayaLPPreflightBlock? {
        let prefix = pool.split(separator: ".", maxSplits: 1).first.map { String($0).uppercased() } ?? ""
        let api = MayaChainAPIService()

        async let mimir = try? await api.getMimirValues()
        async let height = try? await api.getLastBlock()
        async let inbounds = try? await MayachainService.shared.fetchInboundAddressOrThrow(bypassCache: true)
        async let pools = try? await api.getNodePools()

        let inbound = await inbounds?.first { $0.chain.uppercased() == prefix }
        let status = await pools?.first { $0.asset.caseInsensitiveCompare(pool) == .orderedSame }?.status
        return evaluate(
            pool: pool,
            isPairedAdd: isPairedAdd,
            mimir: await mimir,
            height: await height,
            inbound: inbound,
            poolStatus: status
        )
    }
}
