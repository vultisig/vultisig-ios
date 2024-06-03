//
//  BaseService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 18/04/2024.
//

import Foundation
import BigInt

class BaseService: RpcEvmService {
    static let rpcEndpoint = Endpoint.baseServiceRpcService
    static let shared = BaseService(rpcEndpoint)
}

class ArbitrumService: RpcEvmService {
    static let rpcEndpoint = Endpoint.arbitrumOneServiceRpcService
    static let shared = ArbitrumService(rpcEndpoint)
}

class PolygonService: RpcEvmService {
    static let rpcEndpoint = Endpoint.polygonServiceRpcService
    static let shared = PolygonService(rpcEndpoint)
}

class OptimismService: RpcEvmService {
    static let rpcEndpoint = Endpoint.optimismServiceRpcService
    static let shared = OptimismService(rpcEndpoint)
}

class CronosService: RpcEvmService {
    static let rpcEndpoint = Endpoint.cronosServiceRpcService
    static let shared = CronosService(rpcEndpoint)
}

class ZksyncService: RpcEvmService {
    static let rpcEndpoint = Endpoint.zksyncServiceRpcService
    static let shared = ZksyncService(rpcEndpoint)
}

class BlastService: RpcEvmService {
    static let rpcEndpoint = Endpoint.blastServiceRpcService
    static let shared = BlastService(rpcEndpoint)
    
    func getTokens(_ address: String) async -> [Token] {
        return await super.getTokens(urlString: Endpoint.blastServiceToken(address))
    }
}

class BnbService: RpcEvmService {
    static let rpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BnbService(rpcEndpoint)
    
    func getTokens(_ address: String) async -> [Token] {
        return await super.getTokens(urlString: Endpoint.bscServiceToken(address))
    }
}
