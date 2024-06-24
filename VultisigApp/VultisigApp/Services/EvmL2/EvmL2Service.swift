//
//  BaseService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 18/04/2024.
//

import Foundation
import BigInt

class BaseService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.baseServiceRpcService
    static let shared = BaseService(rpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return []
    }
}

class ArbitrumService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.arbitrumOneServiceRpcService
    static let shared = ArbitrumService(rpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return []
    }
}

class PolygonService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.polygonServiceRpcService
    static let shared = PolygonService(rpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return []
    }
}

class OptimismService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.optimismServiceRpcService
    static let shared = OptimismService(rpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return []
    }
}

class CronosService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.cronosServiceRpcService
    static let shared = CronosService(rpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return []
    }
}

class ZksyncService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.zksyncServiceRpcService
    static let shared = ZksyncService(rpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return []
    }
}

class BlastService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.blastServiceRpcService
    static let shared = BlastService(rpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(urlString: Endpoint.blastServiceToken(nativeToken.address)).map{
            $0.toCoinMeta(nativeToken: nativeToken)
        }
    }
}

class BnbService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BnbService(rpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(urlString: Endpoint.bscServiceToken(nativeToken.address)).map{
            $0.toCoinMeta(nativeToken: nativeToken)
        }
    }
}
