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
                return await EvmServiceStruct.getTokensStandard(
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
    
    static func getConfig(forChain chain: Chain) throws -> EvmServiceConfig {
        guard let config = configurations[chain] else {
            throw RpcEvmServiceError.rpcError(code: 500, message: "EVM service not found")
        }
        return config
    }
}
