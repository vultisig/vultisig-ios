import Foundation
import BigInt

class AvalancheService: RpcEvmService, EvmTokenServiceProtocol {
    static let avaxRpcEndpoint = Endpoint.avalancheServiceRpcService
    static let shared = AvalancheService(avaxRpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return []
    }
}
