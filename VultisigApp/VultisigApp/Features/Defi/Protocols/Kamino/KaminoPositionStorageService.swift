//
//  KaminoPositionStorageService.swift
//  VultisigApp
//

import BigInt
import Foundation
import SwiftData

/// `@MainActor` reads and upserts of the `KaminoPosition` cache.
///
/// Mirrors `YieldPositionStorageService`: one row per `(vault address, vault
/// key)`, id-keyed, no delete-stale. Rows are created when the user enables a
/// vault and are never deleted by a refresh — a refresh only reports what the
/// vault holds.
struct KaminoPositionStorageService {

    @MainActor
    func position(for vault: Vault, vaultAddress: String) -> KaminoPosition? {
        vault.kaminoPositions.first { $0.vaultAddress == vaultAddress }
    }

    /// Addresses the user turned on, intersected with the registry: a row whose
    /// vault has since left the allow-list stops being shown and stops counting
    /// towards the DeFi total, rather than being rendered with no descriptor.
    @MainActor
    func enabledVaultAddresses(for vault: Vault) -> Set<String> {
        Set(
            vault.kaminoPositions
                .filter { $0.isEnabled && KaminoVaultRegistry.isAllowed($0.vaultAddress) }
                .map(\.vaultAddress)
        )
    }

    /// Applies a whole Earn selection in ONE save.
    ///
    /// Batched rather than per-vault so a failure cannot leave half the user's
    /// selection committed: every row and the backup mirror move together or
    /// not at all. Only registry vaults are considered, so an address the app
    /// no longer curates can never be turned on.
    ///
    /// A newly enabled vault gets a zero row at the vault's pinned decimal
    /// scales — those scale every amount, and the SOL vault's differ (9 token,
    /// 6 share). Disabling never clears the snapshot: it does not withdraw from
    /// the vault, so the last-known position is still true and re-enabling
    /// paints it immediately.
    @MainActor
    func setEnabledVaults(_ addresses: Set<String>, for vault: Vault) throws {
        var didChange = false

        for descriptor in KaminoVaultRegistry.allowList {
            let isEnabled = addresses.contains(descriptor.address)
            if let existing = position(for: vault, vaultAddress: descriptor.address) {
                guard existing.isEnabled != isEnabled else { continue }
                existing.isEnabled = isEnabled
                didChange = true
            } else if isEnabled {
                Storage.shared.insert(makeZeroPosition(descriptor: descriptor, for: vault))
                didChange = true
            }
        }

        let mirror = KaminoVaultRegistry.allowList
            .map(\.address)
            .filter { addresses.contains($0) }
        if vault.enabledKaminoVaults != mirror {
            vault.enabledKaminoVaults = mirror
            didChange = true
        }

        guard didChange else { return }
        try saveAndNotify()
    }

    /// Turns a single vault on or off, leaving the rest of the selection alone.
    @MainActor
    func setEnabled(
        _ isEnabled: Bool,
        descriptor: KaminoVaultDescriptor,
        for vault: Vault
    ) throws {
        var addresses = enabledVaultAddresses(for: vault)
        if isEnabled {
            addresses.insert(descriptor.address)
        } else {
            addresses.remove(descriptor.address)
        }
        try setEnabledVaults(addresses, for: vault)
    }

    /// Materialises the selection an imported backup carries as plain addresses
    /// into position rows.
    ///
    /// A backup encodes `Vault.enabledKaminoVaults`, not the position cache, so
    /// a restored vault arrives with the user's choice but no rows — and every
    /// read here is row-driven, which would leave their deposits invisible.
    /// Idempotent and additive: it only ever creates a missing row, never
    /// disables one, so it is safe to call on every load.
    @MainActor
    func hydrateEnabledVaultsIfNeeded(for vault: Vault) throws {
        let missing = vault.enabledKaminoVaults
            .compactMap { KaminoVaultRegistry.descriptor(for: $0) }
            .filter { position(for: vault, vaultAddress: $0.address) == nil }

        guard !missing.isEmpty else { return }
        for descriptor in missing {
            Storage.shared.insert(makeZeroPosition(descriptor: descriptor, for: vault))
        }
        try saveAndNotify()
    }

    /// Writes refreshed snapshots onto the rows that already exist.
    ///
    /// A snapshot for a vault with no row is skipped rather than inserted: the
    /// row is what records the user's opt-in, so inserting one here would let a
    /// refresh silently enable a vault the user never selected — and roll its
    /// balance into the DeFi total.
    @MainActor
    func upsert(snapshots: [KaminoPositionSnapshot], for vault: Vault) throws {
        let existingByAddress = Dictionary(
            vault.kaminoPositions.map { ($0.vaultAddress, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        var didChange = false
        for snapshot in snapshots {
            guard let existing = existingByAddress[snapshot.vaultAddress] else { continue }
            existing.apply(snapshot)
            didChange = true
        }

        guard didChange else { return }
        try saveAndNotify()
    }
}

private extension KaminoPositionStorageService {
    @MainActor
    func makeZeroPosition(descriptor: KaminoVaultDescriptor, for vault: Vault) -> KaminoPosition {
        KaminoPosition(
            vaultAddress: descriptor.address,
            isEnabled: true,
            shares: KaminoShareAmount(baseUnits: 0, decimals: descriptor.sharesDecimals),
            tokenAmount: KaminoTokenAmount(baseUnits: 0, decimals: descriptor.tokenDecimals),
            vault: vault
        )
    }

    /// Same signal `DefiPositionsStorageService` posts, for the same reason:
    /// `@ObservedObject` does not propagate an in-place mutation of a nested
    /// `@Model` array back to the parent vault, so views deriving a balance from
    /// the relationship need to be told.
    @MainActor
    func saveAndNotify() throws {
        try Storage.shared.save()
        NotificationCenter.default.post(name: .defiPositionsDidChange, object: nil)
    }
}
