import Foundation
import BigInt

class EthService: RpcEvmService, EvmTokenServiceProtocol {
    static let ethRpcEndpoint = Endpoint.ethServiceRpcService
    static let shared = EthService(ethRpcEndpoint)
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        return await super.getTokens(urlString: Endpoint.ethServiceToken(nativeToken.address)).map{
            $0.toCoinMeta(nativeToken: nativeToken)
        }
    }
}
