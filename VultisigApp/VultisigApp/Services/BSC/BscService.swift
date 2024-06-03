import Foundation
import BigInt

class BSCService: RpcEvmService, EvmTokenServiceProtocol {
    static let bscRpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BSCService(bscRpcEndpoint)
    
    func getTokens(address: String) async -> [Token] {
        return await super.getTokens(urlString: Endpoint.bscServiceToken(address))
    }
}
