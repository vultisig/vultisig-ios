import Foundation
import BigInt

class AvalancheService: RpcEvmService {
    static let avaxRpcEndpoint = Endpoint.avalancheServiceRpcService
    static let shared = AvalancheService(avaxRpcEndpoint)
}
