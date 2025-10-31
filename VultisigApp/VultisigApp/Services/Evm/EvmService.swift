//
//  BaseService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 18/04/2024.
//

import Foundation
import BigInt

class BSCService: RpcEvmService, EvmTokenServiceProtocol {
    static let bscRpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BSCService(bscRpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class EthService: RpcEvmService, EvmTokenServiceProtocol {
    static let ethRpcEndpoint = Endpoint.ethServiceRpcService
    static let shared = EthService(ethRpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class EthSepoliaService: RpcEvmService, EvmTokenServiceProtocol {
    static let ethRpcEndpoint = Endpoint.ethSepoliaServiceRpcService
    static let shared = EthSepoliaService(ethRpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return [TokensStore.Token.ethSepolia]
    }
}

class AvalancheService: RpcEvmService, EvmTokenServiceProtocol {
    static let avaxRpcEndpoint = Endpoint.avalancheServiceRpcService
    static let shared = AvalancheService(avaxRpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

// L2s

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

class MantleService: RpcEvmService, EvmTokenServiceProtocol {
    static let defaultMantleSwapLimit = BigInt("3000000000")
    static let rpcEndpoint = Endpoint.mantleServiceRpcService
    static let shared = MantleService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class TronEvmService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.tronEvmServiceRpc
    static let shared = TronEvmService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class HyperliquidService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.hyperliquidServiceRpcService
    static let shared = HyperliquidService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}

class SeiService: RpcEvmService, EvmTokenServiceProtocol {
    static let rpcEndpoint = Endpoint.seiServiceRpcService
    static let shared = SeiService(rpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}
