import Foundation
import SwiftUI
import WalletCore

class SolanaService {
    static let shared = SolanaService()
    
    private init() {}
    
    private let rpcURL = URL(string: Endpoint.solanaServiceRpc)!
    private let publicNodeRpcURL = URL(string: "https://solana-rpc.publicnode.com")!
    
    private let jsonDecoder = JSONDecoder()
    
    private let TOKEN_PROGRAM_ID_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
    
    // Rate limiting for PublicNode
    private let requestQueue = DispatchQueue(label: "com.vultisig.solana.requests", attributes: .concurrent)
    private let requestSemaphore = DispatchSemaphore(value: 5) // Max 5 concurrent requests
    private var lastRequestTime = Date()
    private let minRequestInterval: TimeInterval = 0.1 // 100ms between requests
    
    // Request tracking
    private var requestCount = 0
    private var requestCountLock = NSLock()
    private var requestStartTime = Date()
    
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
    
    private var tokenAccountCache = [TokenAccountCacheKey: TokenAccountCacheValue]()
    private let tokenAccountCacheLock = NSLock()
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    
    // Clear expired cache entries
    private func cleanExpiredCache() {
        tokenAccountCacheLock.lock()
        defer { tokenAccountCacheLock.unlock() }
        
        let now = Date()
        tokenAccountCache = tokenAccountCache.filter { _, value in
            now.timeIntervalSince(value.timestamp) < cacheExpirationTime
        }
    }
    
    // Determine which RPC to use based on the method
    private func getRpcUrl(for method: String) -> URL {
        // Use PublicNode for account-related queries
        let accountMethods = [
            "getTokenAccountsByOwner",
            "getAccountInfo",
            "getMultipleAccounts"
        ]
        
        if accountMethods.contains(method) {
            print("Using PublicNode RPC for \(method)")
            return publicNodeRpcURL
        } else {
            print("Using Vultisig RPC for \(method)")
            return rpcURL
        }
    }
    
    func sendSolanaTransaction(encodedTransaction: String) async throws
    -> String?
    {
        do {
            print("\n=== SENDING SOLANA TRANSACTION ===")
            print("Time: \(Date())")
            print("Transaction length: \(encodedTransaction.count)")
            print("First 100 chars: \(String(encodedTransaction.prefix(100)))")
            
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendTransaction",
                "params": [encodedTransaction],
            ]
            
            let data = try await postRequest(with: requestBody, url: publicNodeRpcURL)
            
            // Log raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw RPC Response: \(jsonString)")
            }
            
            if let errorMessage = Utils.extractResultFromJson(
                fromData: data, path: "error.message") as? String
            {
                let lowercaseError = errorMessage.lowercased()
                
                // Check for specific blockhash-related errors
                if lowercaseError.contains("blockhash not found") ||
                    lowercaseError.contains("has already been processed") {
                    // For Token-2022, blockhash errors often mask the real issue
                    if errorMessage.contains("Error processing Instruction") {
                        // The transaction was actually processed but failed
                        // Continue to check for the real error below
                    } else {
                        return "Transaction failed: Blockhash expired. This happens when signing takes too long. Please try again with all devices ready to sign quickly."
                    }
                }
                
                // Check for simulation failures (often due to insufficient balance or wrong token account)
                if lowercaseError.contains("simulation failed") {
                    // Try to extract more specific error details
                    if lowercaseError.contains("insufficient") {
                        return "Transaction failed: Insufficient balance or funds to cover fees."
                    }
                    if lowercaseError.contains("account does not exist") {
                        return "Transaction failed: Token account not found. Make sure you have this token in your wallet."
                    }
                    if lowercaseError.contains("incorrect program id") {
                        return "Transaction failed: Incorrect token program. This may be a Token-2022 token requiring special handling."
                    }
                    if lowercaseError.contains("invalid seeds") || lowercaseError.contains("associated address does not match") || lowercaseError.contains("provided owner is not allowed") {
                        return "Transaction failed: Cannot create token account for Token-2022. The recipient needs to manually create a token account first using a wallet like Phantom or Solflare."
                    }
                    
                    // Return the full error message for debugging
                    return "Transaction simulation failed: \(errorMessage)"
                }
                
                // Generic timeout handling
                if lowercaseError.contains("time out") ||
                    lowercaseError.contains("expired") {
                    return "Transaction timeout. Please ensure all devices sign within 60 seconds and try again."
                }
                
                // Return the original error for other cases
                return errorMessage
            }
            
            let response = try jsonDecoder.decode(
                SolanaRPCResponse<String>.self, from: data)
            
            print("Transaction successful!")
            print("Signature: \(response.result ?? "nil")")
            print("==================================\n")
            
            return response.result
        } catch {
            print("Error in sendSolanaTransaction:")
            print("Error details: \(error)")
            print("==================================\n")
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
        // Check cache first
        let cacheKey = TokenAccountCacheKey(walletAddress: walletAddress, mintAddress: mintAddress)
        
        tokenAccountCacheLock.lock()
        if let cachedValue = tokenAccountCache[cacheKey] {
            let age = Date().timeIntervalSince(cachedValue.timestamp)
            tokenAccountCacheLock.unlock()
            
            if age < cacheExpirationTime {
                print("\n=== USING CACHED TOKEN ACCOUNT ===")
                print("Wallet: \(walletAddress)")
                print("Mint: \(mintAddress)")
                print("Cached account: \(cachedValue.accountAddress)")
                print("Is Token-2022: \(cachedValue.isToken2022)")
                print("Cache age: \(String(format: "%.1f", age)) seconds")
                print("==================================\n")
                
                return (cachedValue.accountAddress, cachedValue.isToken2022)
            } else {
                // Remove expired entry
                tokenAccountCacheLock.lock()
                tokenAccountCache.removeValue(forKey: cacheKey)
                tokenAccountCacheLock.unlock()
            }
        } else {
            tokenAccountCacheLock.unlock()
        }
        
        do {
            print("\n=== FETCHING TOKEN ACCOUNT ===")
            print("Wallet: \(walletAddress)")
            print("Mint: \(mintAddress)")
            
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
            
            // Will automatically use PublicNode due to the method
            let data = try await postRequest(with: requestBody, url: rpcURL)
            
            // Log raw response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("API Response (truncated): \(String(jsonString.prefix(500)))")
                
                // Parse and log specific fields for debugging
                if let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = jsonData["result"] as? [String: Any],
                   let value = result["value"] as? [[String: Any]],
                   let firstAccount = value.first,
                   let accountData = firstAccount["account"] as? [String: Any] {
                    print("First account owner: \(accountData["owner"] ?? "unknown")")
                }
            }
            
            let parsedData = try parseSolanaTokenResponse(jsonData: data)
            let accounts: [SolanaService.SolanaTokenAccount] = parsedData.result
                .value
            
            print("Found \(accounts.count) account(s)")
            
            guard let associatedAccount = accounts.first else {
                print("No accounts returned from getTokenAccountsByOwner - checking deterministic ATAs")
                // No account returned – may be RPC issue. Try direct account look-ups for the
                // two deterministic associated-token addresses (legacy SPL + Token-2022).
                
                let ownerAddress = SolanaAddress(string: walletAddress)!
                let defaultAta = ownerAddress.defaultTokenAddress(tokenMintAddress: mintAddress)
                let token2022Ata = ownerAddress.token2022Address(tokenMintAddress: mintAddress)
                
                let addressesToProbe = [defaultAta, token2022Ata]
                print("Probing ATAs: \(addressesToProbe)")
                
                for ata in addressesToProbe.compactMap({ $0 }) {
                    let infoRequest: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "getAccountInfo",
                        "params": [ata, ["encoding": "jsonParsed"]],
                    ]
                    do {
                        print("Checking ATA: \(ata)")
                        // Will automatically use PublicNode due to the method
                        let infoData = try await postRequest(with: infoRequest, url: rpcURL)
                        if let jsonObj = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any],
                           let result = jsonObj["result"] as? [String: Any],
                           let value = result["value"] as? [String: Any] {
                            // Account exists
                            let ownerProgram = value["owner"] as? String ?? ""
                            let isT22 = ownerProgram == TOKEN_PROGRAM_ID_2022
                            print("✓ Found ATA via getAccountInfo: \(ata)")
                            print("  Owner program: \(ownerProgram)")
                            print("  Is Token-2022: \(isT22)")
                            
                            // Cache the result
                            tokenAccountCacheLock.lock()
                            tokenAccountCache[cacheKey] = TokenAccountCacheValue(
                                accountAddress: ata,
                                isToken2022: isT22,
                                timestamp: Date()
                            )
                            tokenAccountCacheLock.unlock()
                            
                            return (ata, isT22)
                        } else {
                            print("✗ ATA not found: \(ata)")
                        }
                    } catch {
                        print("✗ Error checking ATA \(ata): \(error.localizedDescription)")
                        // ignore probe errors and continue
                    }
                }
                
                print("No account found for this mint after all probes")
                return (.empty, false)
            }
            
            let accountOwner = associatedAccount.account.owner
            let isToken2022 = accountOwner == TOKEN_PROGRAM_ID_2022
            
            print("Account found: \(associatedAccount.pubkey)")
            print("Account owner program: \(accountOwner)")
            print("Is Token-2022: \(isToken2022)")
            
            // Add validation check
            if accountOwner != TOKEN_PROGRAM_ID_2022 && accountOwner != "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" {
                print("WARNING: Unknown token program ID: \(accountOwner)")
            }
            
            print("==============================\n")
            
            // Cache the result
            tokenAccountCacheLock.lock()
            tokenAccountCache[cacheKey] = TokenAccountCacheValue(
                accountAddress: associatedAccount.pubkey,
                isToken2022: isToken2022,
                timestamp: Date()
            )
            tokenAccountCacheLock.unlock()
            
            return (associatedAccount.pubkey, isToken2022)
        } catch {
            print("Error in fetchTokenAssociatedAccountByOwner:")
            print("Error details: \(error)")
            print("This could cause incorrect token program detection!")
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
    
    private func postRequest(with body: [String: Any], url: URL) async throws -> Data {
        // Extract method from request body to determine which RPC to use
        if let method = body["method"] as? String {
            let selectedUrl = getRpcUrl(for: method)
            return try await performPostRequest(with: body, url: selectedUrl)
        }
        
        // Default to the URL passed in if method not found
        return try await performPostRequest(with: body, url: url)
    }
    
    private func performPostRequest(with body: [String: Any], url: URL) async throws -> Data {
        // Track request count
        requestCountLock.lock()
        requestCount += 1
        let currentRequestNumber = requestCount
        requestCountLock.unlock()
        
        // Apply rate limiting for PublicNode
        let isPublicNode = url == publicNodeRpcURL
        
        if isPublicNode {
            // Wait for semaphore (limits concurrent requests)
            await withCheckedContinuation { continuation in
                requestQueue.async {
                    self.requestSemaphore.wait()
                    continuation.resume()
                }
            }
            
            // Ensure minimum time between requests
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
            if timeSinceLastRequest < minRequestInterval {
                let waitTime = minRequestInterval - timeSinceLastRequest
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            lastRequestTime = Date()
        }
        
        defer {
            if isPublicNode {
                requestSemaphore.signal()
            }
        }
        
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.httpMethod = "POST"
            request.addValue(
                "application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: body, options: [])
            
            let startTime = Date()
            print("\n--- RPC Request #\(currentRequestNumber) ---")
            print("URL: \(url)")
            if let bodyData = request.httpBody,
               let bodyString = String(data: bodyData, encoding: .utf8),
               let jsonObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let method = jsonObj["method"] as? String {
                print("Method: \(method)")
                print("Start time: \(startTime)")
                
                // Log wallet address for token account queries
                if method == "getTokenAccountsByOwner",
                   let params = jsonObj["params"] as? [Any],
                   let walletAddress = params.first as? String {
                    print("Wallet: \(walletAddress)")
                }
            }
            
            let (data, response) = try await URLSession.shared.data(
                for: request)
            
            let endTime = Date()
            let elapsedTime = endTime.timeIntervalSince(startTime)
            
            // Log HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                print("Status: \(httpResponse.statusCode)")
                
                // Check for rate limiting
                if httpResponse.statusCode == 429 {
                    print("⚠️ RATE LIMIT HIT!")
                    if let retryAfter = httpResponse.allHeaderFields["Retry-After"] as? String {
                        print("Retry-After: \(retryAfter)")
                    }
                }
                
                // Log other error statuses
                if httpResponse.statusCode >= 400 {
                    print("❌ HTTP Error: \(httpResponse.statusCode)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Error response: \(errorString)")
                    }
                }
            }
            
            print("Response time: \(String(format: "%.3f", elapsedTime)) seconds")
            print("-------------------\n")
            
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
            print("Error in performPostRequest: \(error.localizedDescription)")
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
    
    func checkAccountExists(address: String) async throws -> (exists: Bool, isToken2022: Bool) {
        // Check if this address is already in our token account cache
        // This is a quick check to avoid unnecessary RPC calls for known accounts
        tokenAccountCacheLock.lock()
        for (_, value) in tokenAccountCache where value.accountAddress == address {
            let age = Date().timeIntervalSince(value.timestamp)
            if age < cacheExpirationTime {
                tokenAccountCacheLock.unlock()
                print("✓ Account \(address) found in cache (Token-2022: \(value.isToken2022))")
                return (true, value.isToken2022)
            }
        }
        tokenAccountCacheLock.unlock()
        
        do {
            print("Checking if account exists: \(address)")
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getAccountInfo",
                "params": [address, ["encoding": "jsonParsed"]],
            ]
            
            // Will automatically use PublicNode due to the method
            let data = try await postRequest(with: requestBody, url: rpcURL)
            
            if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = jsonObj["result"] as? [String: Any],
               let value = result["value"] as? [String: Any],
               let owner = value["owner"] as? String {
                // Account exists
                let isToken2022 = owner == TOKEN_PROGRAM_ID_2022
                print("✓ Account \(address) exists with owner: \(owner)")
                return (true, isToken2022)
            }
            
            // Account doesn't exist
            print("✗ Account \(address) does not exist")
            return (false, false)
        } catch {
            print("Error checking account existence: \(error)")
            // In case of error, assume account doesn't exist
            return (false, false)
        }
    }
    
    func resetRequestStats() {
        requestCountLock.lock()
        let totalRequests = requestCount
        let duration = Date().timeIntervalSince(requestStartTime)
        requestCount = 0
        requestStartTime = Date()
        requestCountLock.unlock()
        
        if totalRequests > 0 {
            print("\n📊 Request Statistics:")
            print("Total requests: \(totalRequests)")
            print("Duration: \(String(format: "%.2f", duration)) seconds")
            print("Average: \(String(format: "%.2f", Double(totalRequests) / duration)) requests/second")
            print("=====================================\n")
        }
    }
    
    func clearTokenAccountCache() {
        tokenAccountCacheLock.lock()
        defer { tokenAccountCacheLock.unlock() }
        
        let count = tokenAccountCache.count
        tokenAccountCache.removeAll()
        print("Cleared \(count) cached token accounts")
    }
    
    func getCacheStats() -> (entries: Int, hitRate: Double) {
        tokenAccountCacheLock.lock()
        defer { tokenAccountCacheLock.unlock() }
        
        return (tokenAccountCache.count, 0.0) // Hit rate would need additional tracking
    }
    
}
