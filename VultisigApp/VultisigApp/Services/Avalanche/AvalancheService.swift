import Foundation
import BigInt

class AvalancheService: RpcEvmService, EvmTokenServiceProtocol {
    static let avaxRpcEndpoint = Endpoint.avalancheServiceRpcService
    static let shared = AvalancheService(avaxRpcEndpoint)
    
    func getTokens(chain:Chain, address: String) async -> [Coin] {
        return []
    }
}
