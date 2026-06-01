//
//  CustomRPCOverride.swift
//  VultisigApp
//

import Foundation
import SwiftData

/// App-wide custom RPC endpoint override, keyed by `Chain.rawValue`.
///
/// This is the persisted source of truth for a user-supplied RPC URL that
/// replaces the hardcoded default for a given chain. It is intentionally NOT a
/// relationship on `Vault` — overrides apply globally to every vault.
///
/// The networking layer never reads this model directly. SwiftData `@Model`
/// instances must only be touched on the MainActor, but RPC URL resolution
/// happens off the main actor (on background tasks during balance/fee/broadcast
/// calls). `CustomRPCStore` bridges that gap: it owns a thread-safe in-memory
/// mirror that the networking layer reads synchronously, and only the store's
/// MainActor methods read/write these rows.
@Model
final class CustomRPCOverride {
    @Attribute(.unique) var chainRaw: String
    var url: String

    init(chainRaw: String, url: String) {
        self.chainRaw = chainRaw
        self.url = url
    }
}
