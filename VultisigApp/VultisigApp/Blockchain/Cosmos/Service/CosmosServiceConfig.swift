//
//  CosmosServiceConfig.swift
//  VultisigApp
//

import Foundation

struct CosmosServiceConfig {
    let chain: Chain

    /// The resolved custom RPC override URL for this chain, baked in at
    /// construction time by the factory. `nil` means no override is set and the
    /// hardcoded default host is used.
    let overrideURL: URL?

    init(chain: Chain, resolver: RPCEndpointResolving = CustomRPCStore.shared) {
        self.chain = chain
        if let override = resolver.url(for: chain), let url = URL(string: override) {
            self.overrideURL = url
        } else {
            self.overrideURL = nil
        }
    }

    /// REST host for this chain. All `/cosmos/*`, `/ibc/*`, `/cosmwasm/*`
    /// paths are appended to this by `CosmosAPI`.
    var baseURL: URL? {
        // App-wide custom RPC override wins over the hardcoded default. Falls
        // through to the default switch when no override is set for this chain.
        if let overrideURL {
            return overrideURL
        }
        switch chain {
        case .gaiaChain:
            return URL(string: "https://cosmos-rest.publicnode.com")
        case .dydx:
            return URL(string: "https://dydx-rest.publicnode.com")
        case .kujira:
            return URL(string: "https://kujira-rest.publicnode.com")
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
