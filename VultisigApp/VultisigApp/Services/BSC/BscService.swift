import Foundation
import BigInt

class BSCService: RpcEvmService, EvmTokenServiceProtocol {
    static let bscRpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BSCService(bscRpcEndpoint)
    
    func getTokens(nativeToken: Coin, address: String) async -> [Coin] {
        return await super.getTokens(urlString: Endpoint.bscServiceToken(address)).map{
            $0.toCoin(nativeToken: nativeToken, priceRate: .zero)
        }
    }
}
