import Foundation
import SwiftUI
import WalletCore

class SolanaService {
    static let shared = SolanaService()
    
    private init() {}
    
    private let rpcURL = URL(string: Endpoint.solanaServiceRpc)!
    
    private let jsonDecoder = JSONDecoder()
    
    private let TOKEN_PROGRAM_ID_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
    
    func sendSolanaTransaction(encodedTransaction: String) async throws
    -> String?
    {
        do {
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendTransaction",
                "params": [encodedTransaction],
            ]
            
            let data = try await postRequest(with: requestBody, url: rpcURL)
            
            if let errorMessage = Utils.extractResultFromJson(
                fromData: data, path: "error.message") as? String
            {
                return errorMessage
            }
            
            let response = try jsonDecoder.decode(
                SolanaRPCResponse<String>.self, from: data)
            
            return response.result
        } catch {
            print("Error in sendSolanaTransaction:")
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
        } catch {
            print("Error in fetchSolanaJupiterTokenInfoList:")
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
        } catch {
            print("Error in fetchSolanaJupiterTokenList: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchTokenAssociatedAccountByOwner(
        for walletAddress: String, mintAddress: String
    ) async throws -> (String, Bool) {
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
            let accounts: [SolanaService.SolanaTokenAccount] = parsedData.result
                .value
            
            guard let associatedAccount = accounts.first else {
                return (.empty, false)
            }
            
            let isToken2022 = associatedAccount.account.owner == TOKEN_PROGRAM_ID_2022
            
            return (associatedAccount.pubkey, isToken2022)
        } catch {
            print("Error in fetchTokenAssociatedAccountByOwner:")
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
        } catch {
            print("Error in fetchTokens: \(error)")
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
    
    private func postRequest(with body: [String: Any], url: URL) async throws
    -> Data
    {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.httpMethod = "POST"
            request.addValue(
                "application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: body, options: [])
            
            let (data, response) = try await URLSession.shared.data(
                for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               let cacheControl = httpResponse.allHeaderFields["Cache-Control"]
                as? String,
               cacheControl.contains("max-age") == false
            {
                
                // Set a default caching duration if none is provided
                let userInfo = ["Cache-Control": "max-age=120"]  // 2 minutes
                let cachedResponse = CachedURLResponse(
                    response: httpResponse, data: data, userInfo: userInfo,
                    storagePolicy: .allowed)
                URLCache.shared.storeCachedResponse(
                    cachedResponse, for: request)
            }
            
            return data
        } catch {
            print("Error in postRequest: \(error.localizedDescription)")
            throw error
        }
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
}
