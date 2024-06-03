import Foundation
import BigInt

class AvalancheService: RpcEvmService, EvmTokenServiceProtocol {
    static let avaxRpcEndpoint = Endpoint.avalancheServiceRpcService
    static let shared = AvalancheService(avaxRpcEndpoint)
    
    func getTokens(address: String) async -> [Token] {
        return []
    }
}
