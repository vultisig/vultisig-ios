//
//  CustomRPCDefaultEndpoint.swift
//  VultisigApp
//

import Foundation

/// Resolves the hardcoded default RPC endpoint for a chain, bypassing any user
/// override. Used to populate the read-only "DEFAULT ENDPOINT" card in the
/// editor so the user can see what they are overriding (and what Reset restores).
///
/// There is no single global `Chain -> endpoint` map; each chain family owns its
/// own default. This collects those per-family defaults in one place. EVM reads
/// the static config dictionary directly; the remaining families expose a
/// `static let` default host the override layer falls back to.
enum CustomRPCDefaultEndpoint {

    /// The default endpoint URL string for `chain`, or `nil` if the chain has no
    /// configurable default (it should never appear in `CustomRPCSupportedChains`).
    static func string(for chain: Chain) -> String? {
        if let config = EvmServiceConfig.configurations[chain] {
            return config.rpcEndpoint
        }

        switch chain {
        case .gaiaChain, .dydx, .kujira, .osmosis, .terra, .terraClassic, .noble, .akash:
            return CosmosServiceConfig(chain: chain, resolver: NoOverrideResolver()).baseURL?.absoluteString
        case .thorChain:
            return ThorchainMainnetAPI.defaultLCDHost.absoluteString
        case .mayaChain:
            return MayaChainAPI.defaultHost.absoluteString
        case .solana:
            return SolanaAPI.rpcBaseURL.absoluteString
        case .ripple:
            return RippleAPI.defaultHost.absoluteString
        case .sui:
            return SuiService.defaultRPCURL.absoluteString
        case .bittensor:
            return Endpoint.bittensorServiceRpc
        case .polkadot:
            return Endpoint.polkadotServiceRpc
        case .ton:
            return TonAPI.defaultHost.absoluteString
        case .tron:
            return TronAPI.defaultHost.absoluteString
        default:
            return nil
        }
    }
}

/// A resolver that never returns an override, so override-aware config types
/// fall back to their hardcoded default.
private struct NoOverrideResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}
