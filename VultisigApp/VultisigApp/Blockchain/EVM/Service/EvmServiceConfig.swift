//
//  EvmServiceConfig.swift
//  VultisigApp
//
//  Value type configuration for EVM services
//

import Foundation
import BigInt

struct EvmServiceConfig {
    let chain: Chain
    let rpcEndpoint: String
    let tokenProvider: TokenProvider

    enum TokenProvider {
        case standard
        case custom([CoinMeta])
        case sepolia

        func getTokens(nativeToken: CoinMeta, address: String, rpcService: RpcServiceStruct) async -> [CoinMeta] {
            switch self {
            case .standard:
                // Mirror the SDK + Windows discovery path: 1inch `/balance` +
                // `/token` for the chains where 1inch publishes data,
                // TokensStore-iteration fallback for the rest. The old
                // Alchemy `getTokenBalances` + heuristic spam blocklist was
                // dropping legit small-caps — see #4334.
                if EvmCoinFinder.isSupported(chain: nativeToken.chain) {
                    return await EvmCoinFinder.find(chain: nativeToken.chain, address: address)
                }
                return await EvmServiceStruct.getTokensFallback(
                    nativeToken: nativeToken,
                    address: address,
                    rpcService: rpcService
                )
            case .custom(let tokens):
                return tokens
            case .sepolia:
                return [TokensStore.Token.ethSepolia]
            }
        }
    }

    static let configurations: [Chain: EvmServiceConfig] = [
        .ethereum: EvmServiceConfig(
            chain: .ethereum,
            rpcEndpoint: Endpoint.ethServiceRpcService,
            tokenProvider: .standard
        ),
        .ethereumSepolia: EvmServiceConfig(
            chain: .ethereumSepolia,
            rpcEndpoint: Endpoint.ethSepoliaServiceRpcService,
            tokenProvider: .sepolia
        ),
        .bscChain: EvmServiceConfig(
            chain: .bscChain,
            rpcEndpoint: Endpoint.bscServiceRpcService,
            tokenProvider: .standard
        ),
        .avalanche: EvmServiceConfig(
            chain: .avalanche,
            rpcEndpoint: Endpoint.avalancheServiceRpcService,
            tokenProvider: .standard
        ),
        .base: EvmServiceConfig(
            chain: .base,
            rpcEndpoint: Endpoint.baseServiceRpcService,
            tokenProvider: .standard
        ),
        .arbitrum: EvmServiceConfig(
            chain: .arbitrum,
            rpcEndpoint: Endpoint.arbitrumOneServiceRpcService,
            tokenProvider: .standard
        ),
        .polygon: EvmServiceConfig(
            chain: .polygon,
            rpcEndpoint: Endpoint.polygonServiceRpcService,
            tokenProvider: .standard
        ),
        .polygonV2: EvmServiceConfig(
            chain: .polygonV2,
            rpcEndpoint: Endpoint.polygonServiceRpcService,
            tokenProvider: .standard
        ),
        .optimism: EvmServiceConfig(
            chain: .optimism,
            rpcEndpoint: Endpoint.optimismServiceRpcService,
            tokenProvider: .standard
        ),
        .blast: EvmServiceConfig(
            chain: .blast,
            rpcEndpoint: Endpoint.blastServiceRpcService,
            tokenProvider: .standard
        ),
        .cronosChain: EvmServiceConfig(
            chain: .cronosChain,
            rpcEndpoint: Endpoint.cronosServiceRpcService,
            tokenProvider: .standard
        ),
        .zksync: EvmServiceConfig(
            chain: .zksync,
            rpcEndpoint: Endpoint.zksyncServiceRpcService,
            tokenProvider: .standard
        ),
        .mantle: EvmServiceConfig(
            chain: .mantle,
            rpcEndpoint: Endpoint.mantleServiceRpcService,
            tokenProvider: .standard
        ),
        .hyperliquid: EvmServiceConfig(
            chain: .hyperliquid,
            rpcEndpoint: Endpoint.hyperliquidServiceRpcService,
            tokenProvider: .standard
        ),
        .sei: EvmServiceConfig(
            chain: .sei,
            rpcEndpoint: Endpoint.seiServiceRpcService,
            tokenProvider: .standard
        ),
        .tron: EvmServiceConfig(
            chain: .tron,
            rpcEndpoint: Endpoint.tronEvmServiceRpc,
            tokenProvider: .standard
        )
    ]

    /// The single resolution point for EVM custom RPC overrides. The resolver
    /// is injected (defaulting to the shared store) so the produced config is a
    /// pure value type and callers never reach into global state. Returns the
    /// unmodified default config when no override is set for this chain.
    static func getConfig(
        forChain chain: Chain,
        resolver: RPCEndpointResolving = CustomRPCStore.shared
    ) throws -> EvmServiceConfig {
        guard let config = configurations[chain] else {
            throw RpcEvmServiceError.rpcError(code: 500, message: "EVM service not found")
        }
        // `.tron` is special: the custom-RPC override the user configures is a
        // TronGrid-compatible REST endpoint (`/wallet/*`) consumed by `TronAPI`,
        // not an EVM JSON-RPC node. Applying it to this EVM-rpc proxy host would
        // POST `eth_*` calls to a REST surface and break the TVM contract path,
        // so the EVM-rpc host stays on its default proxy regardless of override.
        guard chain != .tron, let override = resolver.url(for: chain) else {
            return config
        }
        return EvmServiceConfig(
            chain: config.chain,
            rpcEndpoint: override,
            tokenProvider: config.tokenProvider
        )
    }
}
