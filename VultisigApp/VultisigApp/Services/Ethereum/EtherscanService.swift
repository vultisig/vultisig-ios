import Foundation
import BigInt

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
