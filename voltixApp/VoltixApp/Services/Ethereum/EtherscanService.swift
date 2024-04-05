import Foundation
import BigInt

class EthService: RpcEvmService {
    static let ethRpcEndpoint = Endpoint.ethServiceRpcService
    static let shared = BSCService(ethRpcEndpoint)
}
