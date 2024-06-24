import Foundation
import BigInt

class BSCService: RpcEvmService, EvmTokenServiceProtocol {
    static let bscRpcEndpoint = Endpoint.bscServiceRpcService
    static let shared = BSCService(bscRpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(urlString: Endpoint.bscServiceToken(nativeToken.address)).map{
            $0.toCoinMeta(nativeToken: nativeToken)
        }
    }
}
