//
//  KaminoPosition.swift
//  VultisigApp
//

import BigInt
import Foundation
import SwiftData

/// Persisted Kamino Earn position, keyed `(vaultAddress, pubKeyECDSA)`.
///
/// This model carries the user's per-vault opt-in as well as the position
/// snapshot, which is why the Earn segment needs no fourth `DefiPositions`
/// bucket. `DefiPositions` is `Codable` and its `init(from:)` decodes every
/// bucket with a *required* `decode`, and vault backups encode those rows — so a
/// naively added fourth bucket would break decoding of backups that already
/// exist. Enablement lives here instead and that hazard never arises.
///
/// The snapshot has to be persisted rather than held in a view model because
/// `DefiBalanceService` computes the Solana DeFi total and position count
/// **synchronously from persisted state**; a value that only exists inside a
/// view model can never reach it.
///
/// Amounts are stored as exact base-unit integer strings plus their decimal
/// scale, matching `KaminoShareAmount` / `KaminoTokenAmount`. Shares and tokens
/// have independent scales — 6 and 9 on the SOL vault — so a single "amount"
/// column would be ambiguous, and a human-units field would put a division in
/// front of every read.
@Model
final class KaminoPosition {
    @Attribute(.unique) var id: String

    /// The kVault this position is held in. Always a `KaminoVaultRegistry`
    /// address; readers resolve the descriptor from it rather than trusting any
    /// metadata stored alongside.
    var vaultAddress: String

    /// Whether the user selected this vault under "Manage positions". Disabling
    /// does NOT withdraw — it only hides the vault and drops it out of the DeFi
    /// total — so the snapshot below is deliberately kept.
    var isEnabled: Bool

    /// Share balance in SHARE base units, as an exact decimal-integer string.
    var sharesBaseUnits: String
    var shareDecimals: Int

    /// `sharesBaseUnits` valued through `metrics.tokensPerShare`, in TOKEN base
    /// units. Never through `metrics.sharePrice`, which is USD-denominated and
    /// overstates a non-dollar vault by the token's price (~74× on Allez SOL).
    var tokenBaseUnits: String
    var tokenDecimals: Int

    /// 30-day APY as a fraction (`0.0391` = 3.91%), not a percentage.
    var apy30d: Decimal?

    /// Lifetime profit and loss in the underlying token, from `/pnl`.
    var pnlToken: Decimal?

    var lastUpdated: Date

    @Relationship(inverse: \Vault.kaminoPositions) var vault: Vault?

    init(
        vaultAddress: String,
        isEnabled: Bool,
        shares: KaminoShareAmount,
        tokenAmount: KaminoTokenAmount,
        apy30d: Decimal? = nil,
        pnlToken: Decimal? = nil,
        vault: Vault
    ) {
        self.vaultAddress = vaultAddress
        self.isEnabled = isEnabled
        self.sharesBaseUnits = String(shares.baseUnits)
        self.shareDecimals = shares.decimals
        self.tokenBaseUnits = String(tokenAmount.baseUnits)
        self.tokenDecimals = tokenAmount.decimals
        self.apy30d = apy30d
        self.pnlToken = pnlToken
        self.lastUpdated = .now
        self.vault = vault
        self.id = Self.makeID(vaultAddress: vaultAddress, pubKeyECDSA: vault.pubKeyECDSA)
    }

    /// One row per vault per vault-key. `id` is `@Attribute(.unique)`, so two
    /// rows built with the same pair silently collapse into one.
    static func makeID(vaultAddress: String, pubKeyECDSA: String) -> String {
        "\(vaultAddress)_\(pubKeyECDSA)"
    }

    /// The exact share balance. `nil` only if the stored string were ever
    /// corrupted — readers treat that as "no position" rather than zero-filling.
    var shares: KaminoShareAmount? {
        BigInt(sharesBaseUnits).map { KaminoShareAmount(baseUnits: $0, decimals: shareDecimals) }
    }

    /// The exact deposited amount in the vault's underlying token.
    var tokenAmount: KaminoTokenAmount? {
        BigInt(tokenBaseUnits).map { KaminoTokenAmount(baseUnits: $0, decimals: tokenDecimals) }
    }

    /// Human-units deposited amount for display and fiat conversion. Zero when
    /// the stored value cannot be read, so a corrupted row is never counted.
    var tokenAmountDecimal: Decimal {
        tokenAmount?.decimalValue ?? .zero
    }

    /// Applies a fresh snapshot. `isEnabled` is deliberately untouched: a
    /// refresh reports what the vault holds, never whether the user wants to see
    /// it.
    func apply(_ snapshot: KaminoPositionSnapshot) {
        sharesBaseUnits = String(snapshot.shares.baseUnits)
        shareDecimals = snapshot.shares.decimals
        tokenBaseUnits = String(snapshot.tokenAmount.baseUnits)
        tokenDecimals = snapshot.tokenAmount.decimals
        apy30d = snapshot.apy30d
        pnlToken = snapshot.pnlToken
        lastUpdated = .now
    }
}

/// A refreshed position, ready to be written to the persisted row. A value type
/// so the network layer never hands a `@Model` across an isolation boundary.
struct KaminoPositionSnapshot: Hashable {
    let vaultAddress: String
    let shares: KaminoShareAmount
    let tokenAmount: KaminoTokenAmount
    let apy30d: Decimal?
    let pnlToken: Decimal?
}
