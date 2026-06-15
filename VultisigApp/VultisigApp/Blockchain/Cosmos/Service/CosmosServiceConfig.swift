//
//  CosmosServiceConfig.swift
//  VultisigApp
//

import Foundation

struct CosmosServiceConfig {
    let chain: Chain

    /// Resolves the custom RPC override for this chain. Held so `baseURL` can
    /// apply the override through the shared resolution helper at access time.
    private let resolver: RPCEndpointResolving

    /// The resolved custom RPC override URL for this chain, or `nil` when no
    /// override is set (the hardcoded default host is used).
    var overrideURL: URL? {
        resolver.url(for: chain).flatMap { URL(string: $0) }
    }

    init(chain: Chain, resolver: RPCEndpointResolving = CustomRPCStore.shared) {
        self.chain = chain
        self.resolver = resolver
    }

    /// REST host for this chain. All `/cosmos/*`, `/ibc/*`, `/cosmwasm/*`
    /// paths are appended to this by `CosmosAPI`. The app-wide custom RPC
    /// override wins over the hardcoded default for this chain.
    var baseURL: URL? {
        // For supported chains the override layers over the hardcoded default.
        // For unsupported chains (no default) fall back to the bare override so
        // behavior matches the pre-refactor `overrideURL ?? default` exactly.
        guard let defaultHost else { return overrideURL }
        return resolver.resolvedURL(for: chain, default: defaultHost)
    }

    /// The hardcoded default REST host for this chain, or `nil` for chains this
    /// config does not support.
    private var defaultHost: URL? {
        switch chain {
        case .gaiaChain:
            return URL(string: "https://cosmos-rest.publicnode.com")
        case .dydx:
            return URL(string: "https://dydx-rest.publicnode.com")
        case .kujira:
            return URL(string: "https://kujira-api.polkachu.com")
        case .osmosis:
            return URL(string: "https://osmosis-rest.publicnode.com")
        case .terra:
            return URL(string: "https://terra-lcd.publicnode.com")
        case .terraClassic:
            return URL(string: "https://terra-classic-lcd.publicnode.com")
        case .noble:
            return URL(string: "https://noble-api.polkachu.com")
        case .akash:
            return URL(string: "https://akash-rest.publicnode.com")
        case .qbtc:
            return URL(string: "https://api.vultisig.com/qbtc-rpc")
        default:
            return nil
        }
    }

    /// Terra and Terra Classic expose balances under the
    /// `spendable_balances` REST path; every other chain uses `balances`.
    var usesSpendableBalances: Bool {
        switch chain {
        case .terra, .terraClassic:
            return true
        default:
            return false
        }
    }

    static func getConfig(
        forChain chain: Chain,
        resolver: RPCEndpointResolving = CustomRPCStore.shared
    ) throws -> CosmosServiceConfig {
        switch chain {
        case .gaiaChain, .dydx, .kujira, .osmosis, .terra, .terraClassic, .noble, .akash, .qbtc:
            return CosmosServiceConfig(chain: chain, resolver: resolver)
        default:
            throw CosmosServiceError.unsupportedChain
        }
    }
}

enum CosmosServiceError: Error, LocalizedError {
    case unsupportedChain

    var errorDescription: String? {
        switch self {
        case .unsupportedChain:
            return "Unsupported Cosmos chain"
        }
    }
}
