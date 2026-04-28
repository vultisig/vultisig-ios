import Foundation
import SwiftUI
import WalletCore
import OSLog

enum SolanaServiceError: Error, LocalizedError {
    case rpcError(message: String, code: Int)

    var errorDescription: String? {
        switch self {
        case .rpcError(let message, _):
            return "RPC Error: \(message)"
        }
    }
}

enum SolanaRetryableError: Error, LocalizedError, RetryableBroadcastError {
    case blockhashExpired(message: String)

    var errorDescription: String? {
        switch self {
        case .blockhashExpired(let message):
            return "Transaction failed: Blockhash expired. \(message)"
        }
    }

    var retryReason: BroadcastRetryReason {
        switch self {
        case .blockhashExpired:
            return .staleBlockhash
        }
    }
}

class SolanaService {
    static let shared = SolanaService()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "solana-service")
    private let httpClient: HTTPClientProtocol = HTTPClient()

    private init() {}

    private let TOKEN_PROGRAM_ID_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

    private struct TokenAccountCacheValue {
        let accountAddress: String
        let isToken2022: Bool
        let timestamp: Date
    }

    private var tokenAccountCache = ThreadSafeDictionary<String, (data: TokenAccountCacheValue, timestamp: Date)>()
    private let cacheExpirationTime: TimeInterval = 86400 * 30 // 30 days - token accounts don't change once created

    func sendSolanaTransaction(encodedTransaction: String) async throws -> String? {
        let response = try await httpClient.request(
            SolanaAPI.sendTransaction(encodedTransaction: encodedTransaction),
            responseType: SolanaSendTransactionResponse.self
        )

        if let error = response.data.error {
            // -32002 is Solana's generic preflight-failure code, not specific
            // to expired blockhashes — match on the message instead.
            let lowered = error.message.lowercased()
            if lowered.contains("blockhash not found") ||
                lowered.contains("block height exceeded") {
                throw SolanaRetryableError.blockhashExpired(message: error.message)
            }
            throw SolanaServiceError.rpcError(message: error.message, code: error.code)
        }

        return response.data.result
    }

    func getSolanaBalance(coin: Coin) async throws -> String {
        try await getSolanaBalance(coin: coin.toCoinMeta(), address: coin.address)
    }

    func getSolanaBalance(coin: CoinMeta, address: String) async throws -> String {
        if coin.isNativeToken {
            let response = try await httpClient.request(
                SolanaAPI.getBalance(address: address),
                responseType: SolanaGetBalanceResponse.self
            )
            return response.data.result.value.description
        } else {
            guard
                let balance = try await fetchTokenBalance(
                    for: address,
                    contractAddress: coin.contractAddress
                )
            else { return "0" }

            return balance
        }
    }

    func fetchRecentPrioritizationFees() async throws -> UInt64 {
        let response = try await httpClient.request(
            SolanaAPI.getRecentPrioritizationFees,
            responseType: SolanaGetRecentPrioritizationFeesResponse.self
        )

        let nonZeroFees = response.data.result
            .map { $0.prioritizationFee }
            .filter { $0 > 0 }
            .sorted()

        guard !nonZeroFees.isEmpty else {
            return SolanaHelper.defaultPriorityFeePrice
        }

        let mid = nonZeroFees.count / 2
        if nonZeroFees.count % 2 == 0 {
            return (nonZeroFees[mid - 1] + nonZeroFees[mid]) / 2
        } else {
            return nonZeroFees[mid]
        }
    }

    func fetchRecentBlockhash() async throws -> String? {
        let response = try await httpClient.request(
            SolanaAPI.getLatestBlockhash,
            responseType: SolanaGetLatestBlockhashResponse.self
        )
        return response.data.result.value.blockhash
    }

    func fetchSolanaTokenInfoList(contractAddresses: [String]) async throws
    -> [String: SolanaFmTokenInfo] {
        guard !contractAddresses.isEmpty else {
            return [:]
        }

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
    -> SolanaJupiterToken {
        do {
            let urlString = Endpoint.solanaTokenInfoServiceRpc2(
                tokenAddress: contractAddress)
            let dataResponse = try await Utils.asyncGetRequest(
                urlString: urlString, headers: [:])
            // API returns an array, take the first element
            let tokenInfos = try JSONDecoder().decode(
                [SolanaJupiterToken].self, from: dataResponse)
            guard let tokenInfo = tokenInfos.first else {
                throw NSError(domain: "SolanaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No token info found for address: \(contractAddress)"])
            }
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

        if let cachedValue = Utils.getCachedData(cacheKey: cacheKey, cache: tokenAccountCache, timeInSeconds: cacheExpirationTime) {
            return (cachedValue.accountAddress, cachedValue.isToken2022)
        }

        let response = try await httpClient.request(
            SolanaAPI.getTokenAccountsByOwner(walletAddress: walletAddress, filter: .mint(mintAddress)),
            responseType: SolanaService.SolanaDetailedRPCResult<[SolanaService.SolanaTokenAccount]>.self
        )

        guard let associatedAccount = response.data.result.value.first else {
            return ("", false)
        }

        let isToken2022 = associatedAccount.account.owner == TOKEN_PROGRAM_ID_2022

        let cacheValue = TokenAccountCacheValue(
            accountAddress: associatedAccount.pubkey,
            isToken2022: isToken2022,
            timestamp: Date()
        )
        tokenAccountCache.set(cacheKey, (data: cacheValue, timestamp: Date()))

        return (associatedAccount.pubkey, isToken2022)
    }

    func fetchTokenAccountsByOwner(for walletAddress: String) async throws
    -> [SolanaService.SolanaTokenAccount] {
        let programs: [String] = [
            "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // spl-token
            "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" // spl-token-2022
        ]

        var returnPrograms: [SolanaService.SolanaTokenAccount] = []

        do {
            for program in programs {
                let response = try await httpClient.request(
                    SolanaAPI.getTokenAccountsByOwner(walletAddress: walletAddress, filter: .programId(program)),
                    responseType: SolanaService.SolanaDetailedRPCResult<[SolanaService.SolanaTokenAccount]>.self
                )
                returnPrograms.append(contentsOf: response.data.result.value)
            }
        } catch {
            logger.error("fetchTokenAccountsByOwner: \(error.localizedDescription)")
            return []
        }
        return returnPrograms
    }

    func fetchTokenBalance(for walletAddress: String, contractAddress: String) async throws -> String? {
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
            let accounts: [SolanaTokenAccount] = try await fetchTokenAccountsByOwner(for: walletAddress)

            guard !accounts.isEmpty else {
                return []
            }

            let tokenAddresses = accounts.map {
                $0.account.data.parsed.info.mint
            }

            let tokens = try await fetchTokensInfos(for: tokenAddresses)
            return tokens
        } catch {
            print("Error in fetchTokens: \(error)")
            throw error
        }
    }

    func fetchTokensInfos(for contractAddresses: [String]) async throws -> [CoinMeta] {
        guard !contractAddresses.isEmpty else {
            return []
        }

        let tokenInfos = try await fetchSolanaTokenInfoList(contractAddresses: contractAddresses)

        var coinMetaList = [CoinMeta]()

        for contractAddress in contractAddresses {
            do {
                if let tokenInfo = tokenInfos[contractAddress] {
                    let coinMeta = CoinMeta(
                        chain: .solana,
                        ticker: tokenInfo.tokenMetadata?.onChainInfo?.symbol ?? tokenInfo.tokenList?.symbol ?? "",
                        logo: tokenInfo.tokenList?.image ?? "",
                        decimals: tokenInfo.decimals ?? 0,
                        priceProviderId: tokenInfo.tokenList?.extensions?.coingeckoId ?? "",
                        contractAddress: contractAddress,
                        isNativeToken: false
                    )
                    coinMetaList.append(coinMeta)
                } else {
                    let jupiterTokenInfo = try await fetchSolanaJupiterTokenInfoList(
                        contractAddress: contractAddress)
                    let coinMeta = CoinMeta(
                        chain: .solana,
                        ticker: jupiterTokenInfo.symbol ?? "",
                        logo: jupiterTokenInfo.logoURI ?? "",
                        decimals: jupiterTokenInfo.decimals ?? 0,
                        priceProviderId: jupiterTokenInfo.extensions?.coingeckoId ?? "",
                        contractAddress: contractAddress,
                        isNativeToken: false
                    )
                    coinMetaList.append(coinMeta)
                }
            } catch {
                continue
            }
        }

        return coinMetaList
    }

    static func getTokenUSDValue(contractAddress: String, decimals: Int = 6) async -> Double {

        // Try Jupiter quote first
        do {

            let amountDecimal = 1_000_000

            let urlString: String = Endpoint.solanaTokenQuote(
                inputMint: contractAddress,
                outputMint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                amount: amountDecimal.description,
                slippageBps: "50"
            )

            let dataResponse = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])

            // Try both String and Double for swapUsdValue
            let swapUsdValueAny = Utils.extractResultFromJson(fromData: dataResponse, path: "swapUsdValue")

            let rawAmount: String
            if let strVal = swapUsdValueAny as? String {
                rawAmount = strVal
            } else if let numVal = swapUsdValueAny as? Double {
                rawAmount = String(numVal)
            } else if let numVal = swapUsdValueAny as? NSNumber {
                rawAmount = numVal.stringValue
            } else {
                rawAmount = "0"
            }

            let totalSwapUsd = Double(rawAmount) ?? 0.0

            // swapUsdValue is the total USD for ALL tokens in the swap.
            // Divide by the number of tokens to get per-token price.
            let tokensInSwap = Double(amountDecimal) / pow(10.0, Double(decimals))
            let pricePerToken = tokensInSwap > 0 ? totalSwapUsd / tokensInSwap : 0.0

            return pricePerToken

        } catch {
            // Jupiter quote failed, try Raydium fallback
        }

        // Fallback: Raydium mint price API (covers CLMM pools Jupiter doesn't route to)
        do {
            let raydiumUrl = Endpoint.raydiumMintPrice(mint: contractAddress)
            let raydiumData = try await Utils.asyncGetRequest(urlString: raydiumUrl, headers: [:])

            if let json = try JSONSerialization.jsonObject(with: raydiumData) as? [String: Any],
               let data = json["data"] as? [String: Any],
               let priceStr = data[contractAddress] as? String,
               let price = Double(priceStr), price > 0 {
                return price
            }
        } catch {
            // Raydium fallback also failed
        }

        return 0.0
    }

    func checkAccountExists(address: String) async throws -> (exists: Bool, isToken2022: Bool) {
        let response = try await httpClient.request(
            SolanaAPI.getAccountInfo(address: address),
            responseType: SolanaGetAccountInfoResponse.self
        )

        guard let value = response.data.result.value else {
            return (false, false)
        }

        let isToken2022 = value.owner == TOKEN_PROGRAM_ID_2022
        return (true, isToken2022)
    }

}
