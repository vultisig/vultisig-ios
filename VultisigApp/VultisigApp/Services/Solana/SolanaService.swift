import Foundation
import SwiftUI
import WalletCore

class SolanaService {
    
    static let shared = SolanaService()
    
    private init() {}
    
    private let rpcURL = URL(string: Endpoint.solanaServiceRpc)!
    
    private let jsonDecoder = JSONDecoder()
    
    private let CACHE_TIMEOUT_IN_SECONDS: Double = 120 // 2 minutes
    
    func sendSolanaTransaction(encodedTransaction: String) async throws -> String? {
        
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
        
    }
    
    func getSolanaBalance(coin: Coin) async throws -> (rawBalance: String, priceRate: Double) {
        
        var rawBalance = "0"
        
        let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        
        if coin.isNativeToken {
            
            let data = try await Utils.PostRequestRpc(rpcURL: rpcURL, method: "getBalance", params: [coin.address])
            
            if let totalBalance = Utils.extractResultFromJson(fromData: data, path: "result.value") as? Int64 {
                rawBalance = totalBalance.description
            }
            
        } else {
            
            rawBalance = try await fetchTokenBalance(for: coin.address, contractAddress: coin.contractAddress) ?? "0"
            
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
        
        let data = try await postRequest(with: requestBody)
        
        blockHash = Utils.extractResultFromJson(fromData: data, path: "result.value.blockhash") as? String
        
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
    
    // This method gets the association account between the sender and the token
    // https://www.quicknode.com/guides/solana-development/spl-tokens/how-to-look-up-the-address-of-a-token-account
    func fetchTokenAssociatedAccountByOwner(for walletAddress: String, mintAddress: String) async throws -> String {
        
        let cache_key = "getTokenAccountsByOwner_mint_\(mintAddress)_\(walletAddress)"
        
        if let cachedValue: String = CacheService.shared.getCachedData(for: cache_key, type: String.self) {
            return cachedValue
        }
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getTokenAccountsByOwner",
            "params": [
                walletAddress,
                ["mint": mintAddress], // SPL Token Program ID
                ["encoding": "jsonParsed"]
            ]
        ]
        
        let data = try await postRequest(with: requestBody)
        let parsedData = try parseSolanaTokenResponse(jsonData: data)
        let accounts: [SolanaService.SolanaTokenAccount] = parsedData.result.value
        
        guard let associatedAccount = accounts.first else {
            return .empty
        }
        
        // This is the address we are sending from and to
        let pubkey = associatedAccount.pubkey
        
        try CacheService.shared.setCachedData(pubkey, for: cache_key)
        
        return pubkey
    }
    
    func fetchTokenAccountsByOwner(for walletAddress: String) async throws -> [SolanaService.SolanaTokenAccount] {
        
        let cache_key = "getTokenAccountsByOwner_\(walletAddress)_TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
        
        if let cachedValue: [SolanaService.SolanaTokenAccount] = CacheService.shared.getCachedData(for: cache_key, type: [SolanaService.SolanaTokenAccount].self) {
            return cachedValue
        }
        
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
        
        let data = try await postRequest(with: requestBody)
        let parsedData = try parseSolanaTokenResponse(jsonData: data)
        let accounts: [SolanaService.SolanaTokenAccount] = parsedData.result.value
        
        try CacheService.shared.setCachedData(accounts, for: cache_key)
        
        return accounts
    }
    
    func fetchTokenBalance(for walletAddress: String, contractAddress: String) async throws -> String? {
        
        let accounts: [SolanaTokenAccount] = try await fetchTokenAccountsByOwner(for: walletAddress)
        
        if let token = accounts.first(where: { $0.account.data.parsed.info.mint == contractAddress }) {
            return token.account.data.parsed.info.tokenAmount.amount
        } 
        
        return nil
    }
    
    func fetchTokens(for walletAddress: String) async throws -> [CoinMeta] {
        
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
    
    private func parseSolanaTokenResponse(jsonData: Data) throws -> SolanaService.SolanaDetailedRPCResult<[SolanaService.SolanaTokenAccount]> {
        return try JSONDecoder().decode(SolanaService.SolanaDetailedRPCResult<[SolanaService.SolanaTokenAccount]>.self, from: jsonData)
    }
    
}
