import Foundation
import SwiftUI
import WalletCore
import BigInt

enum SolanaServiceError: Error, LocalizedError {
    case blockhashExpired(message: String)
    case rpcError(message: String, code: Int)
    
    var errorDescription: String? {
        switch self {
        case .blockhashExpired(let message):
            return "Transaction failed: Blockhash expired. \(message)"
        case .rpcError(let message, _):
            return "RPC Error: \(message)"
        }
    }
}

struct SendTransactionResponse: Codable {
    let jsonrpc: String
    let result: String?
    let error: ErrorResponse?
    
    struct ErrorResponse: Codable {
        let code: Int
        let message: String
    }
}

class SolanaService {
    static let shared = SolanaService()
    
    private init() {}
    
    private let rpcURL = URL(string: Endpoint.solanaServiceRpc)!
    
    private let accountQueryMethods = Set([
        "getTokenAccountsByOwner",
        "getAccountInfo",
        "getMultipleAccounts"
    ])
    
    private let jsonDecoder = JSONDecoder()
    
    private let TOKEN_PROGRAM_ID_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
    
    // Token account cache
    private struct TokenAccountCacheKey: Hashable {
        let walletAddress: String
        let mintAddress: String
    }
    
    private struct TokenAccountCacheValue {
        let accountAddress: String
        let isToken2022: Bool
        let timestamp: Date
    }
    
    private var tokenAccountCache = ThreadSafeDictionary<String, (data: TokenAccountCacheValue, timestamp: Date)>()
    private let cacheExpirationTime: TimeInterval = 86400 * 30 // 30 days - token accounts don't change once created
    
    func sendSolanaTransaction(encodedTransaction: String) async throws -> String? {
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sendTransaction",
            "params": [encodedTransaction],
        ]
        
        do {
            let data = try await postRequest(with: requestBody, url: rpcURL)
            
            // Parse response
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for error
                if let error = jsonObject["error"] as? [String: Any] {
                    let errorMessage = error["message"] as? String ?? "Unknown error"
                    let errorCode = error["code"] as? Int ?? -1
                    
                    // Check if it's a blockhash expiration error
                    if errorMessage.contains("Blockhash not found") ||
                        errorMessage.contains("blockhash") ||
                        errorCode == -32002 {
                        throw SolanaServiceError.blockhashExpired(message: errorMessage)
                    }
                    
                    throw SolanaServiceError.rpcError(message: errorMessage, code: errorCode)
                }
                
                // Check for result
                if let result = jsonObject["result"] as? String {
                    return result
                }
            }
            
            let response = try JSONDecoder().decode(SendTransactionResponse.self, from: data)
            return response.result
        } catch {
            throw error
        }
    }
    
    func getSolanaBalance(coin: Coin) async throws -> String {
        if coin.isNativeToken {
            let data = try await Utils.PostRequestRpc(
                rpcURL: rpcURL,
                method: "getBalance",
                params: [coin.address]
            )
            
            guard
                let totalBalance = Utils.extractResultFromJson(
                    fromData: data,
                    path: "result.value"
                ) as? Int64
            else { return "0" }
            
            return totalBalance.description
            
        } else {
            guard
                let balance = try await fetchTokenBalance(
                    for: coin.address,
                    contractAddress: coin.contractAddress
                )
            else { return "0" }
            
            return balance
        }
    }
    
    func fetchRecentBlockhash() async throws -> String? {
        do {
            var blockHash: String? = nil
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getLatestBlockhash",
                "params": [["commitment": "finalized"]],
            ]
            
            let data = try await postRequest(with: requestBody, url: rpcURL)
            blockHash =
            Utils.extractResultFromJson(
                fromData: data, path: "result.value.blockhash") as? String
            return blockHash
        } catch {
            print("Error in fetchRecentBlockhash:")
            throw error
        }
    }
    
    func fetchSolanaTokenInfoList(contractAddresses: [String]) async throws
    -> [String: SolanaFmTokenInfo]
    {
        do {
            let urlString = Endpoint.solanaTokenInfoServiceRpc
            let body: [String: Any] = ["tokens": contractAddresses]
            let dataPayload = try JSONSerialization.data(
                withJSONObject: body, options: [])
            let dataResponse = try await Utils.asyncPostRequest(
                urlString: urlString, headers: [:], body: dataPayload)
            let tokenInfo = try JSONDecoder().decode(
                [String: SolanaFmTokenInfo].self, from: dataResponse)
            return tokenInfo
        } catch {
            print("Error in fetchSolanaTokenInfoList:")
            return [:]
        }
    }
    
    func fetchSolanaJupiterTokenInfoList(contractAddress: String) async throws
    -> SolanaJupiterToken
    {
        do {
            let urlString = Endpoint.solanaTokenInfoServiceRpc2(
                tokenAddress: contractAddress)
            let dataResponse = try await Utils.asyncGetRequest(
                urlString: urlString, headers: [:])
            let tokenInfo = try JSONDecoder().decode(
                SolanaJupiterToken.self, from: dataResponse)
            return tokenInfo
        } catch let error as NSError {
            if error.code == 429 {
                print("Error in fetchSolanaJupiterTokenInfoList: Rate limit exceeded (429)")
            } else {
                print("Error in fetchSolanaJupiterTokenInfoList: \(error.localizedDescription) (Code: \(error.code))")
            }
            throw error
        } catch {
            print("Error in fetchSolanaJupiterTokenInfoList: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchSolanaJupiterTokenList() async throws -> [CoinMeta] {
        do {
            let urlString = Endpoint.solanaTokenInfoList()
            let dataResponse = try await Utils.asyncGetRequest(
                urlString: urlString, headers: [:])
            
            let tokenInfos = try JSONDecoder().decode(
                [SolanaJupiterToken].self, from: dataResponse)
            return tokenInfos.map { jupiterTokenInfo in
                let coinMeta = CoinMeta(
                    chain: .solana,
                    ticker: jupiterTokenInfo.symbol ?? "",
                    logo: jupiterTokenInfo.logoURI ?? "",
                    decimals: jupiterTokenInfo.decimals ?? 0,
                    priceProviderId: jupiterTokenInfo.extensions?.coingeckoId ?? "",
                    contractAddress: jupiterTokenInfo.address ?? "",
                    isNativeToken: false
                )
                return coinMeta
            }
        } catch let error as NSError {
            if error.code == 429 {
                print("Error in fetchSolanaJupiterTokenList: Rate limit exceeded (429)")
            } else {
                print("Error in fetchSolanaJupiterTokenList: \(error.localizedDescription) (Code: \(error.code))")
            }
            throw error
        } catch {
            print("Error in fetchSolanaJupiterTokenList: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchTokenAssociatedAccountByOwner(for ownerAddress: String, mintAddress: String) async throws -> (String, Bool) {
        // First try getTokenAccountsByOwner
        let (tokenAccounts, isToken2022) = try await getTokenAccountsByOwner(walletAddress: ownerAddress, mintAddress: mintAddress)
        
        if !tokenAccounts.isEmpty {
            return (tokenAccounts, isToken2022)
        }
        
        // If getTokenAccountsByOwner returns empty, probe the deterministic ATAs directly
        guard let walletCoreAddress = WalletCore.SolanaAddress(string: ownerAddress) else {
            return ("", false)
        }
        
        // Try standard SPL token ATA first
        if let defaultAta = walletCoreAddress.defaultTokenAddress(tokenMintAddress: mintAddress), !defaultAta.isEmpty {
            let (exists, _) = try await checkAccountExists(address: defaultAta)
            if exists {
                return (defaultAta, false)
            }
        }
        
        // Try Token-2022 ATA
        if let token2022Ata = walletCoreAddress.token2022Address(tokenMintAddress: mintAddress), !token2022Ata.isEmpty {
            let (exists, _) = try await checkAccountExists(address: token2022Ata)
            if exists {
                return (token2022Ata, true)
            }
        }
        
        return ("", false)
    }
    
    func getTokenAccountsByOwner(walletAddress: String, mintAddress: String) async throws -> (String, Bool) {
        // Check cache first
        let cacheKey = "solana-token-account-\(walletAddress)-\(mintAddress)"
        
        if let cachedValue = await Utils.getCachedData(cacheKey: cacheKey, cache: tokenAccountCache, timeInSeconds: cacheExpirationTime) {
            return (cachedValue.accountAddress, cachedValue.isToken2022)
        }
        
        do {
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getTokenAccountsByOwner",
                "params": [
                    walletAddress,
                    ["mint": mintAddress],
                    ["encoding": "jsonParsed"],
                ],
            ]
            
            let data = try await postRequest(with: requestBody, url: rpcURL)
            let parsedData = try parseSolanaTokenResponse(jsonData: data)
            let accounts: [SolanaService.SolanaTokenAccount] = parsedData.result.value
            
            guard let associatedAccount = accounts.first else {
                return ("", false)
            }
            
            let accountOwner = associatedAccount.account.owner
            let isToken2022 = accountOwner == TOKEN_PROGRAM_ID_2022
            
            // Cache the result
            let cacheValue = TokenAccountCacheValue(
                accountAddress: associatedAccount.pubkey,
                isToken2022: isToken2022,
                timestamp: Date()
            )
            tokenAccountCache.set(cacheKey, (data: cacheValue, timestamp: Date()))
            
            return (associatedAccount.pubkey, isToken2022)
        } catch {
            throw error
        }
    }
    
    func fetchTokenAccountsByOwner(for walletAddress: String) async throws
    -> [SolanaService.SolanaTokenAccount]
    {
        let programs: [String] = [
            "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // spl-token
            "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" // spl-token-2022
        ]
        
        var returnPrograms: [SolanaService.SolanaTokenAccount] = []
        
        do {
            for program in programs {
                let requestBody: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "getTokenAccountsByOwner",
                    "params": [
                        walletAddress,
                        [
                            "programId": program
                        ],
                        ["encoding": "jsonParsed"],
                    ],
                ]
                
                let data = try await postRequest(with: requestBody, url: rpcURL)
                let parsedData = try parseSolanaTokenResponse(jsonData: data)
                let items: [SolanaService.SolanaTokenAccount] = parsedData.result.value
                
                for item in items {
                    returnPrograms.append(item)
                }
            }
        } catch {
            print("Error in fetchTokenAccountsByOwner: \(error.localizedDescription)")
            return []
        }
        return returnPrograms
    }
    
    func fetchTokenBalance(for walletAddress: String, contractAddress: String)
    async throws -> String?
    {
        do {
            let accounts: [SolanaTokenAccount] =
            try await fetchTokenAccountsByOwner(for: walletAddress)
            
            if let token = accounts.first(where: {
                $0.account.data.parsed.info.mint.lowercased() == contractAddress.lowercased()
            }) {
                return token.account.data.parsed.info.tokenAmount.amount
            }
            
            return nil
        } catch {
            print("Error in fetchTokenBalance: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchTokens(for walletAddress: String) async throws -> [CoinMeta] {
        do {
            let accounts: [SolanaTokenAccount] =
            try await fetchTokenAccountsByOwner(for: walletAddress)
            let tokenAddresses = accounts.map {
                $0.account.data.parsed.info.mint
            }
            
            var coinMetaList = [CoinMeta]()
            for tokenAddress in tokenAddresses {
                let jupiterTokenInfo: SolanaJupiterToken =
                try await fetchSolanaJupiterTokenInfoList(
                    contractAddress: tokenAddress)
                let coinMeta = CoinMeta(
                    chain: .solana,
                    ticker: jupiterTokenInfo.symbol ?? "",
                    logo: jupiterTokenInfo.logoURI?.description ?? "",
                    decimals: jupiterTokenInfo.decimals ?? 0,
                    priceProviderId: jupiterTokenInfo.extensions?.coingeckoId ?? "",
                    contractAddress: tokenAddress,
                    isNativeToken: false
                )
                coinMetaList.append(coinMeta)
                
            }
            
            return coinMetaList
        } catch {
            print("Error in fetchTokens: \(error)")
            throw error
        }
    }
    
    func fetchTokensInfos(for contractAddresses: [String]) async throws
    -> [CoinMeta]
    {
        do {
            // Fetch token info from the first provider
            let tokenInfos = try await fetchSolanaTokenInfoList(
                contractAddresses: contractAddresses)
            
            var coinMetaList = [CoinMeta]()
            
            for contractAddress in contractAddresses {
                if let tokenInfo = tokenInfos[contractAddress] {
                    let coinMeta = CoinMeta(
                        chain: .solana,
                        ticker: tokenInfo.tokenMetadata.onChainInfo.symbol,
                        logo: tokenInfo.tokenList.image.description,
                        decimals: tokenInfo.decimals,
                        priceProviderId: tokenInfo.tokenList.extensions?
                            .coingeckoId ?? .empty,
                        contractAddress: contractAddress,
                        isNativeToken: false
                    )
                    coinMetaList.append(coinMeta)
                } else {
                    // Fetch from second provider if not found
                    let jupiterTokenInfo: SolanaJupiterToken =
                    try await fetchSolanaJupiterTokenInfoList(
                        contractAddress: contractAddress)
                    let coinMeta = CoinMeta(
                        chain: .solana,
                        ticker: jupiterTokenInfo.symbol ?? "",
                        logo: jupiterTokenInfo.logoURI?.description ?? "",
                        decimals: jupiterTokenInfo.decimals ?? 0,
                        priceProviderId: jupiterTokenInfo.extensions?
                            .coingeckoId ?? "",
                        contractAddress: contractAddress,
                        isNativeToken: false
                    )
                    coinMetaList.append(coinMeta)
                }
            }
            
            return coinMetaList
        } catch let error as NSError {
            if error.code == 429 {
                print("Error in fetchTokensInfos: Rate limit exceeded (429)")
            } else {
                print("Error in fetchTokensInfos: \(error.localizedDescription) (Code: \(error.code))")
            }
            throw error
        } catch {
            print("Error in fetchTokensInfos: \(error)")
            throw error
        }
    }
    
    func fetchHighPriorityFee(account: String) async throws -> UInt64 {
        do {
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
                "params": [[account]],
            ]
            
            let data = try await postRequest(with: requestBody, url: rpcURL)
            let decoder = JSONDecoder()
            let response = try decoder.decode(
                PrioritizationFeeResponse.self, from: data)
            
            let fees = response.result.map { $0.prioritizationFee }
            let nonZeroFees = fees.filter { $0 > 0 }
            
            let highPriorityFee = nonZeroFees.max() ?? 0
            return UInt64(highPriorityFee)
        } catch {
            print("Error in fetchHighPriorityFee:")
            throw error
        }
    }
    
    private func postRequest(with requestBody: [String: Any], url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 10
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        return data
    }
    
    private func parseSolanaTokenResponse(jsonData: Data) throws
    -> SolanaService.SolanaDetailedRPCResult<
        [SolanaService.SolanaTokenAccount]
    >
    {
        do {
            return try JSONDecoder().decode(
                SolanaService.SolanaDetailedRPCResult<
                [SolanaService.SolanaTokenAccount]
                >.self, from: jsonData)
        } catch {
            print("Error in parseSolanaTokenResponse:")
            throw error
        }
    }
    
    static func getTokenUSDValue(contractAddress: String) async -> Double {
        
        do {
            
            let amountDecimal = 1_000_000 // 1 USDC
            
            let urlString: String = Endpoint.solanaTokenQuote(
                inputMint: contractAddress,
                outputMint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                amount: amountDecimal.description,
                slippageBps: "50"
            )
            
            let dataResponse = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
            let rawAmount = Utils.extractResultFromJson(fromData: dataResponse, path: "swapUsdValue") as? String ?? "0"
            
            return Double(rawAmount) ?? 0.0
            
        } catch {
            print("Error in fetchSolanaJupiterTokenInfoList:")
            return 0.0
        }
        
    }
    
    func checkAccountExists(address: String) async throws -> (exists: Bool, isToken2022: Bool) {
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getAccountInfo",
            "params": [address, ["encoding": "jsonParsed"]],
        ]
        
        let data = try await postRequest(with: requestBody, url: rpcURL)
        
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = jsonObj["result"] as? [String: Any],
           let value = result["value"] as? [String: Any] {
            // Account exists
            let ownerProgram = value["owner"] as? String ?? ""
            let isToken2022 = ownerProgram == TOKEN_PROGRAM_ID_2022
            return (true, isToken2022)
        }
        
        return (false, false)
    }
    
    /// Get the fee for a serialized transaction message
    /// - Parameter message: Base64-encoded transaction message
    /// - Returns: Fee in lamports
    func getFeeForMessage(message: String) async throws -> BigInt {
        struct FeeForMessageResponse: Decodable {
            let result: ResultValue
            
            struct ResultValue: Decodable {
                let value: UInt64?
            }
        }
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getFeeForMessage",
            "params": [message, ["commitment": "confirmed"]],
        ]
        
        let data = try await postRequest(with: requestBody, url: rpcURL)
        let response = try JSONDecoder().decode(FeeForMessageResponse.self, from: data)
        
        guard let feeValue = response.result.value else {
            throw SolanaServiceError.rpcError(message: "Failed to get fee for message", code: -1)
        }
        
        return BigInt(feeValue)
    }
    
    /// Get the minimum balance required for rent exemption for a token account (165 bytes)
    /// - Returns: Minimum balance in lamports (typically ~2,039,280 lamports)
    func getMinimumBalanceForRentExemption() async throws -> BigInt {
        struct MinimumBalanceResponse: Decodable {
            let result: UInt64
        }
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getMinimumBalanceForRentExemption",
            "params": [165], // 165 bytes for token account
        ]
        
        let data = try await postRequest(with: requestBody, url: rpcURL)
        let response = try JSONDecoder().decode(MinimumBalanceResponse.self, from: data)
        
        return BigInt(response.result)
    }
    
}
