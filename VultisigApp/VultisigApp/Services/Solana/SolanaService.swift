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
    
    func getSolanaBalance(coin: Coin) async throws -> (rawBalance: String, priceRate: Double) {
        var rawBalance = "0"
        let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        
        do {
            
            if coin.isNativeToken {
                
                let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "getBalance", params: [coin.address])
                
                if let totalBalance = Utils.extractResultFromJson(fromData: data, path: "result.value") as? Int64 {
                    rawBalance = totalBalance.description
                }
                
            } else {
                
                rawBalance = try await fetchTokenBalance(for: coin.address, contractAddress: coin.contractAddress)
                
            }
        } catch {
            print("Error fetching balance: \(error.localizedDescription)")
            throw error
        }
        return (rawBalance, priceRateFiat)
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
    
    func fetchSolanaTokenInfoList(contractAddresses: [String]) async throws -> [String: SolanaFmTokenInfo] {
        let urlString = Endpoint.solanaTokenInfoServiceRpc
        let body: [String: Any] = ["tokens": contractAddresses]
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        let dataResponse = try await Utils.asyncPostRequest(urlString: urlString, headers: [:], body: dataPayload)
        let tokenInfo = try JSONDecoder().decode([String: SolanaFmTokenInfo].self, from: dataResponse)
        return tokenInfo
    }
    
    //TODO: cache the balance
    func fetchTokenAccountsByOwner(for walletAddress: String) async throws -> [SolanaTokenAccount] {
        
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
            let parsedData = try parseSolanaTokenResponse(jsonData: data)
            let accounts: [SolanaTokenAccount] = parsedData.result.value
            
            return accounts
        } catch {
            print("Error fetching tokens: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchTokenBalance(for walletAddress: String, contractAddress: String) async throws -> String {
        
        do {
            
            let accounts: [SolanaTokenAccount] = try await fetchTokenAccountsByOwner(for: walletAddress)
            
            if let token = accounts.first(where: { $0.account.data.parsed.info.mint == contractAddress }) {
                return token.account.data.parsed.info.tokenAmount.amount
            } else {
                return .zero
            }
            
        } catch {
            print("Error fetching tokens: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchTokens(for walletAddress: String) async throws -> [CoinMeta] {
        
        do {
            
            let accounts: [SolanaTokenAccount] = try await fetchTokenAccountsByOwner(for: walletAddress)
            let tokenAddresses = accounts.map { $0.account.data.parsed.info.mint }
            let tokenInfos = try await fetchSolanaTokenInfoList(contractAddresses: tokenAddresses)
            
            let coinMetaList = tokenInfos.map { tokenInfo in
                CoinMeta(
                    chain: .solana,
                    ticker: tokenInfo.value.tokenMetadata.onChainInfo.symbol,
                    logo: tokenInfo.value.tokenList.image.description,
                    decimals: tokenInfo.value.decimals,
                    priceProviderId: tokenInfo.value.tokenList.extensions.coingeckoId ?? .empty,
                    contractAddress: tokenInfo.key,
                    isNativeToken: false
                )
            }
            
            return coinMetaList
            
        } catch {
            print("Error fetching tokens: \(error.localizedDescription)")
            throw error
        }
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
