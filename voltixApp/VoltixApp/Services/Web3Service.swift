import Combine
import web3
import BigInt
import Foundation

class Web3Service: ObservableObject {
    
    let client: EthereumHttpClient
    
    @Published var nonce: BigInt?
    @Published var gasPrice: BigInt?
    
    init() {
        guard let clientUrl = URL(string: "https://mainnet.infura.io/v3/\(AppConfiguration.infuraApiKey)") else {
            fatalError("Invalid client URL")
        }
        self.client = EthereumHttpClient(url: clientUrl, network: EthereumNetwork.mainnet)
    }
    
    func fetchData(_ address: String) async {
        do {
            let fetchedData = try await fetchNonceAndGasPrice(address)
            nonce = BigInt(fetchedData.nonce)
            gasPrice = BigInt(fetchedData.gasPrice)
        } catch {
            print("Error fetching data: \(error)")
        }
    }
    
    private func fetchNonceAndGasPrice(_ address: String) async throws -> (nonce: BigInt, gasPrice: BigInt) {
        let nonce = try await getNonce(address)
        let gasPrice = try await getGasPrice()
        return (nonce, gasPrice)
    }
    
    private func getNonce(_ address: String) async throws -> BigInt {
        let nonce = try await client.eth_getTransactionCount(address: EthereumAddress(address), block: EthereumBlock.Latest)
        return BigInt(nonce)
    }
    
    private func getGasPrice() async throws -> BigInt {
        let gasPrice = try await client.eth_gasPrice()
        return BigInt(gasPrice)
    }
}
