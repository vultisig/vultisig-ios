import Foundation
import BigInt

class EthService: RpcEvmService {
    static let ethRpcEndpoint = Endpoint.ethServiceRpcService
    static let shared = EthService(ethRpcEndpoint)
    
    func getTokens(_ address: String) async -> [Token] {
        return await super.getTokens(urlString: Endpoint.ethServiceToken(address))
    }
}
