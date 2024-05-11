import Foundation
import BigInt

class BSCService: RpcEvmService {
    static let bscRpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BSCService(bscRpcEndpoint)
}
