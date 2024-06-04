import Foundation
import BigInt

class EthService: RpcEvmService, EvmTokenServiceProtocol {
    static let ethRpcEndpoint = Endpoint.ethServiceRpcService
    static let shared = EthService(ethRpcEndpoint)
    
    func getTokens(chain: Chain, address: String) async -> [Coin] {
        return await super.getTokens(urlString: Endpoint.ethServiceToken(address)).map{
            $0.toCoin(chain: chain, address: address, priceRate: .zero)
        }
    }
}
