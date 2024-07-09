import Foundation
import SwiftUI
import WalletCore

class SolanaService {
    static let shared = SolanaService()
    private init() {}
    
    private let rpcURL = URL(string: Endpoint.solanaServiceRpc)!
    private let jsonDecoder = JSONDecoder()
    
    func sendSolanaTransaction(encodedTransaction: String) async -> String? {
        do {
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendTransaction",
                "params": [encodedTransaction]
            ]
            let data = try await postRequest(with: requestBody)
            
            if let errorMessage = Utils.extractResultFromJson(fromData: data, path: "error.message") as? String {
                return errorMessage
            }
            
            let response = try jsonDecoder.decode(SolanaRPCResponse<String>.self, from: data)
            return response.result
            
        } catch {
            
            
            
            print("Error sending transaction: \(error.localizedDescription)")
        }
        return nil
    }
    
    func getSolanaBalance(coin: Coin) async throws -> (rawBalance: String, priceRate: Double){
        var rawBalance = "0"
        let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        
        do {
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "getBalance", params:  [coin.address])
            
            if let totalBalance = Utils.extractResultFromJson(fromData: data, path: "result.value") as? Int64 {
                rawBalance = totalBalance.description
            }            
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
            throw error
        }
        return (rawBalance,priceRateFiat)
    }
    
    func fetchRecentBlockhash() async throws -> String? {
        var blockHash: String? = nil
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getLatestBlockhash",
            "params": [["commitment": "finalized"]]
        ]
        do {
            let data = try await postRequest(with: requestBody)
            blockHash = Utils.extractResultFromJson(fromData: data, path: "result.value.blockhash") as? String
        } catch {
            print("Error fetching recent blockhash: \(error.localizedDescription)")
            throw error
        }
        return blockHash
    }
    
    // Token metadata https://raw.githubusercontent.com/solana-labs/token-list/main/src/tokens/solana.tokenlist.json
    // Solana Token   https://solana.com/docs/rpc/http/gettokenaccountsbyowner
    func fetchTokens(for walletAddress: String) async throws -> [CoinMeta] {
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getTokenAccountsByOwner",
            "params": [
                walletAddress,
                ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"], // SPL Token Program ID
                ["encoding": "jsonParsed"]
            ]
        ]
        do {
            let data = try await postRequest(with: requestBody)
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let result = jsonResponse["result"] as? [String: Any],
               let value = result["value"] as? [[String: Any]] {
                
                var coinMetaList: [CoinMeta] = []
                
                for tokenAccount in value {
                    if let accountData = tokenAccount["account"] as? [String: Any],
                       let data = accountData["data"] as? [String: Any],
                       let parsed = data["parsed"] as? [String: Any],
                       let info = parsed["info"] as? [String: Any],
                       let mint = info["mint"] as? String,
                       let decimals = info["tokenAmount"] as? [String: Any],
                       let decimalsValue = decimals["decimals"] as? Int {
                        
                        let coinMeta = CoinMeta(
                            chain: .solana,
                            ticker: mint,
                            logo: "",  // You may need to fetch this from a token metadata service
                            decimals: decimalsValue,
                            priceProviderId: "",
                            contractAddress: mint,
                            isNativeToken: info["isNative"] as? Bool ?? false
                        )
                        coinMetaList.append(coinMeta)
                    }
                }
                
                return coinMetaList
            }
        } catch {
            print("Error fetching tokens: \(error.localizedDescription)")
            throw error
        }
        return []
    }
    
    func fetchHighPriorityFee(account: String) async throws -> UInt64 {
        
        struct PrioritizationFeeResponse: Decodable {
            let result: [FeeObject]
        }
        
        struct FeeObject: Decodable {
            let prioritizationFee: Int
            let slot: Int
        }
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getRecentPrioritizationFees",
            "params": [[account]]
        ]
        
        let data = try await postRequest(with: requestBody)
        let decoder = JSONDecoder()
        let response = try decoder.decode(PrioritizationFeeResponse.self, from: data)
        
        let fees = response.result.map { $0.prioritizationFee }
        let nonZeroFees = fees.filter { $0 > 0 }
        
        // Calculate the high priority fee
        let highPriorityFee = nonZeroFees.max() ?? 0
        
        return UInt64(highPriorityFee)
    }

    private func postRequest(with body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
