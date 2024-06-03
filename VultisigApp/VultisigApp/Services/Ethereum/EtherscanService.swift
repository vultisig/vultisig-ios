import Foundation
import BigInt

class EthService: RpcEvmService, EvmTokenServiceProtocol {
    static let ethRpcEndpoint = Endpoint.ethServiceRpcService
    static let shared = EthService(ethRpcEndpoint)
    
    func getTokens(address: String) async -> [Token] {
        return await super.getTokens(urlString: Endpoint.ethServiceToken(address))
    }
}
