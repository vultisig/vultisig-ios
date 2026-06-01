//
//  RPCEndpointResolving.swift
//  VultisigApp
//

import Foundation

/// Abstracts the lookup of a user-configured custom RPC endpoint for a chain.
///
/// The networking layer resolves overrides through this protocol instead of
/// reaching into a global singleton, so the resolution site is an injected
/// dependency: production wires `CustomRPCStore.shared`, tests inject a fake.
/// Implementations must be safe to call synchronously from any thread (the
/// balance / fee / broadcast paths resolve off the MainActor) and must not
/// touch SwiftData.
protocol RPCEndpointResolving: Sendable {
    /// Returns the user's custom RPC URL for `chain`, or `nil` when no override
    /// is set (the caller falls back to its hardcoded default).
    func url(for chain: Chain) -> String?
}

extension CustomRPCStore: RPCEndpointResolving {}
