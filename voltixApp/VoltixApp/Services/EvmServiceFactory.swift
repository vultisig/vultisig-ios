//
//  EvmFactoryService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 04/04/2024.
//

import Foundation

class EvmServiceFactory {
    static func getService(forChain coin: Coin) throws -> RpcEvmService {
        switch coin.chain {
        case .ethereum:
            return EthService.shared
        case .bscChain:
            return BSCService.shared
        case .avalanche:
            return AvalancheService.shared
        default:
            throw RpcEvmServiceError.rpcError(code: 500, message: "EVM service not found")
        }
    }
}
