import Foundation
import BigInt

class BSCService: RpcEvmService, EvmTokenServiceProtocol {
    static let bscRpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BSCService(bscRpcEndpoint)
    
    override func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(nativeToken: nativeToken)
    }
}
