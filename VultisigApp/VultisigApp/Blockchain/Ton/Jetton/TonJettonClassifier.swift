//
//  TonJettonClassifier.swift
//  VultisigApp
//

import Foundation

/// Decides how far a jetton can be trusted, from what the registry lists and
/// what the jetton claims to be. Pure and synchronous: the decision is the part
/// that has to be provable, so it holds no cache, does no I/O and takes the
/// registry as an argument.
enum TonJettonClassifier {

    /// The tier for one jetton master.
    ///
    /// A listed address is verified whatever it calls itself. An unlisted one is
    /// scam when the indexer flags it, or when its symbol or name collapses onto
    /// a listed jetton's — the fake-USDT pattern, where the counterfeit is
    /// distinguishable from the real asset only by address. Anything else is
    /// unverified: a real holding we know nothing about.
    static func classify(
        address: String,
        symbol: String?,
        name: String?,
        isFlaggedScam: Bool?,
        registry: TonJettonRegistry
    ) -> TokenVerification {
        if let listed = registry.entry(for: address) {
            return listed.verification
        }
        if isFlaggedScam == true {
            return .scam
        }
        if registry.impersonates(symbol) || registry.impersonates(name) {
            return .scam
        }
        return .unverified
    }

    /// Convenience over the metadata a discovery page already carries.
    static func classify(
        master: TonJettonMasterMetadata,
        registry: TonJettonRegistry
    ) -> TokenVerification {
        classify(
            address: master.address,
            symbol: master.symbol,
            name: master.name,
            isFlaggedScam: master.isFlaggedScam,
            registry: registry
        )
    }
}
