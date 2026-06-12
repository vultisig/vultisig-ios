//
//  UnstakeMetadata.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

import Foundation

/// Maturity gate for an unstake CTA.
///
/// Persisted inside `StakePosition` (a `@Model`) as an encoded `Codable` value. Rather than baking
/// an absolute unlock `Date` at fetch time — which freezes maturity into a stale snapshot and never
/// re-derives on later view appearances — this holds the RAW block inputs and the height/timestamp
/// the read was taken at, then recomputes maturity live on every gate evaluation. This mirrors the
/// Android `computeMaturityStatus` contract (`remaining = lastDepositHeight + maturityBlocks -
/// currentHeight`) and its `UNKNOWN` state for reads that could not be verified.
struct UnstakeMetadata: Hashable, Codable {
    /// On-chain height of the member's last deposit.
    let lastDepositHeight: Int64
    /// Maturity window in blocks (read live from mimir).
    let maturityBlocks: Int64
    /// Chain height observed when this snapshot was taken.
    let snapshotHeight: Int64
    /// Wall-clock time (seconds since 1970) when this snapshot was taken; used to project the
    /// height forward so the gate re-derives between refreshes instead of staying frozen.
    let snapshotTimestamp: TimeInterval
    /// `true` when the maturity/height read could not be verified (RPC failure). The CTA stays
    /// disabled but the UI explains why instead of leaving an unexplained grey button.
    let isUnknown: Bool

    /// Seconds per Maya block; matches Android `MAYA_BLOCK_TIME_SECONDS`.
    private static let blockTimeSeconds: Double = 6

    init(
        lastDepositHeight: Int64,
        maturityBlocks: Int64,
        snapshotHeight: Int64,
        snapshotTimestamp: TimeInterval,
        isUnknown: Bool = false
    ) {
        self.lastDepositHeight = lastDepositHeight
        self.maturityBlocks = maturityBlocks
        self.snapshotHeight = snapshotHeight
        self.snapshotTimestamp = snapshotTimestamp
        self.isUnknown = isUnknown
    }

    /// Represents a read that failed verification: maturity is unknown, CTA stays gated.
    static let unknown = UnstakeMetadata(
        lastDepositHeight: 0,
        maturityBlocks: 0,
        snapshotHeight: 0,
        snapshotTimestamp: 0,
        isUnknown: true
    )

    /// Projects the snapshot height forward by the wall-clock elapsed since the snapshot, so the
    /// gate keeps advancing between successful refreshes rather than comparing a frozen value.
    private func projectedHeight(at referenceDate: Date) -> Int64 {
        guard snapshotTimestamp > 0 else { return snapshotHeight }
        let elapsed = referenceDate.timeIntervalSince1970 - snapshotTimestamp
        guard elapsed > 0 else { return snapshotHeight }
        let elapsedBlocks = Int64(elapsed / Self.blockTimeSeconds)
        return snapshotHeight + elapsedBlocks
    }

    /// Blocks remaining until maturity, derived live from the projected height. `0` when mature.
    func remainingBlocks(at referenceDate: Date = Date()) -> Int64 {
        guard !isUnknown else { return maturityBlocks }
        let remaining = lastDepositHeight + maturityBlocks - projectedHeight(at: referenceDate)
        return max(0, remaining)
    }

    /// Seconds remaining until maturity, derived live. `0` when mature.
    func remainingSeconds(at referenceDate: Date = Date()) -> TimeInterval {
        Double(remainingBlocks(at: referenceDate)) * Self.blockTimeSeconds
    }

    /// Mature (and verified) ⇒ unstake allowed. Unknown ⇒ gated.
    func canUnstake(at referenceDate: Date = Date()) -> Bool {
        guard !isUnknown else { return false }
        return remainingBlocks(at: referenceDate) == 0
    }

    func unstakeMessage(for coin: CoinMeta, at referenceDate: Date = Date()) -> String? {
        guard coin == TokensStore.cacao else { return nil }

        if isUnknown {
            return "cacaoUnstakeMaturityUnknownMessage".localized
        }

        let secondsRemaining = remainingSeconds(at: referenceDate)
        guard secondsRemaining > 0 else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2

        guard let timeString = formatter.string(from: secondsRemaining) else {
            return nil
        }

        return String(format: "cacaoUnstakeMaturityMessage".localized, timeString)
    }
}

// MARK: - Migration-safe decoding

extension UnstakeMetadata {
    private enum CodingKeys: String, CodingKey {
        case lastDepositHeight
        case maturityBlocks
        case snapshotHeight
        case snapshotTimestamp
        case isUnknown
        // Legacy shape: an absolute unlock date persisted by older builds.
        case unstakeAvailableDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let lastDepositHeight = try container.decodeIfPresent(Int64.self, forKey: .lastDepositHeight) {
            self.lastDepositHeight = lastDepositHeight
            self.maturityBlocks = try container.decodeIfPresent(Int64.self, forKey: .maturityBlocks) ?? 0
            self.snapshotHeight = try container.decodeIfPresent(Int64.self, forKey: .snapshotHeight) ?? 0
            self.snapshotTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .snapshotTimestamp) ?? 0
            self.isUnknown = try container.decodeIfPresent(Bool.self, forKey: .isUnknown) ?? false
            return
        }

        // Legacy persisted row: rebuild raw inputs from the frozen unlock date so the row keeps
        // gating sanely until the next successful refresh overwrites it. The blocks-remaining
        // anchor is derived from the legacy date relative to its own snapshot timestamp.
        let legacyUnlock = try container.decodeIfPresent(TimeInterval.self, forKey: .unstakeAvailableDate) ?? 0
        let now = Date().timeIntervalSince1970
        let secondsRemaining = max(0, legacyUnlock - now)
        // Round up: flooring could let a migrated row unlock up to one block (~6s) early.
        let blocksRemaining = Int64(ceil(secondsRemaining / Self.blockTimeSeconds))

        self.lastDepositHeight = 0
        self.maturityBlocks = blocksRemaining
        self.snapshotHeight = 0
        self.snapshotTimestamp = now
        self.isUnknown = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lastDepositHeight, forKey: .lastDepositHeight)
        try container.encode(maturityBlocks, forKey: .maturityBlocks)
        try container.encode(snapshotHeight, forKey: .snapshotHeight)
        try container.encode(snapshotTimestamp, forKey: .snapshotTimestamp)
        try container.encode(isUnknown, forKey: .isUnknown)
    }
}
