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
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class ArbitrumService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.arbitrumOneServiceRpcService
    static let shared = ArbitrumService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class PolygonService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.polygonServiceRpcService
    static let shared = PolygonService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class OptimismService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.optimismServiceRpcService
    static let shared = OptimismService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class CronosService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.cronosServiceRpcService
    static let shared = CronosService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class ZksyncService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.zksyncServiceRpcService
    static let shared = ZksyncService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class BlastService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.blastServiceRpcService
    static let shared = BlastService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class BnbService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BnbService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}
