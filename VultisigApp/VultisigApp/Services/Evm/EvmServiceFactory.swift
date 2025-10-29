//
//  EvmFactoryService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 04/04/2024.
//

import Foundation

class EvmServiceFactory {

    static func getService(forChain chain: Chain) throws -> (RpcEvmService & EvmTokenServiceProtocol) {
        switch chain {
        case .ethereum:
            return EthService.shared
        case .ethereumSepolia:
            return EthSepoliaService.shared
        case .bscChain:
            return BSCService.shared
        case .avalanche:
            return AvalancheService.shared
        case .base:
            return BaseService.shared
        case .arbitrum:
            return ArbitrumService.shared
        case .polygon, .polygonV2:
            return PolygonService.shared
        case .optimism:
            return OptimismService.shared
        case .blast:
            return BlastService.shared
        case .cronosChain:
            return CronosService.shared
        case .zksync:
            return ZksyncService.shared
        case .mantle:
            return MantleService.shared
        case .hyperliquid:
            return HyperliquidService.shared
        case .tron:
            return TronEvmService.shared
        default:
            throw RpcEvmServiceError.rpcError(code: 500, message: "EVM service not found")
        }
    }
}
