import Foundation
import BigInt

class BSCService: RpcEvmService, EvmTokenServiceProtocol {
    static let bscRpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BSCService(bscRpcEndpoint)
    
    func getTokens(chain: Chain, address: String) async -> [Coin] {
        return await super.getTokens(urlString: Endpoint.bscServiceToken(address)).map{
            $0.toCoin(chain: chain, address: address, priceRate: .zero)
        }
    }
}
