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
    private let httpClient: HTTPClientProtocol

    /// Resolves the Solana custom RPC override. Injected so the API values are
    /// built from a dependency rather than a global reach-in; resolution happens
    /// per request inside `api(_:)` so a runtime override change is picked up
    /// live (the shared mirror updates without a relaunch).
    private let resolver: RPCEndpointResolving

    /// Backoff between client-side rebroadcast attempts. Injectable so tests can
    /// drive the resend loop without real-time delays.
    private let broadcastRetryBackoff: Duration

    /// Number of times a signed transaction is resent when the RPC node reports
    /// the blockhash as not yet seen (propagation lag, not true expiry).
    private static let maxBroadcastAttempts = 3

    init(resolver: RPCEndpointResolving = CustomRPCStore.shared,
         httpClient: HTTPClientProtocol = HTTPClient(),
         broadcastRetryBackoff: Duration = .seconds(2)) {
        self.resolver = resolver
        self.httpClient = httpClient
        self.broadcastRetryBackoff = broadcastRetryBackoff
    }

    /// Builds a pure `SolanaAPI` value with the resolved host and proxy-path
    /// decision baked in. A valid custom override supplies a complete JSON-RPC
    /// endpoint, so the `/solana/` proxy path is dropped; otherwise the default
    /// proxy host keeps it. Both halves are resolved together here so `baseURL`
    /// and `path` cannot disagree. The `TargetType` never consults the resolver.
    private func api(_ method: SolanaAPI.Method) -> SolanaAPI {
        // A valid override supplies a complete JSON-RPC endpoint, so the proxy
        // path is dropped; the no-override default keeps it. The host comes from
        // the shared resolution helper while the proxy-path flag mirrors that
        // same override-present decision so `baseURL` and `path` cannot disagree.
        let hasOverride = resolver.url(for: .solana).flatMap { URL(string: $0) } != nil
        let baseURL = resolver.resolvedURL(for: .solana, default: SolanaAPI.rpcBaseURL)
        return SolanaAPI(baseURL: baseURL, usesProxyPath: !hasOverride, rpcMethod: method)
    }

    private let TOKEN_PROGRAM_ID_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

    private struct TokenAccountCacheValue {
        let accountAddress: String
        let isToken2022: Bool
        let timestamp: Date
    }

    private var tokenAccountCache = ThreadSafeDictionary<String, (data: TokenAccountCacheValue, timestamp: Date)>()
    private let cacheExpirationTime: TimeInterval = 86400 * 30 // 30 days - token accounts don't change once created

    func sendSolanaTransaction(encodedTransaction: String) async throws -> String? {
        for attempt in 1...Self.maxBroadcastAttempts {
            let response = try await httpClient.request(
                api(.sendTransaction(encodedTransaction: encodedTransaction)),
                responseType: SolanaSendTransactionResponse.self
            )

            guard let error = response.data.error else {
                return response.data.result
            }

            // -32002 is Solana's generic preflight-failure code, not specific
            // to expired blockhashes. The structured reason lives in
            // `data.err` ("BlockhashNotFound"); the message is just the generic
            // "Transaction simulation failed". Match on either.
            let structuredErr = error.data?.err?.stringValue ?? ""
            let lowered = (error.message + " " + structuredErr).lowercased()
            // The structured `data.err` form is "BlockhashNotFound" (no spaces);
            // the message form is "Blockhash not found". Match both.
            let isBlockhashNotFound = lowered.contains("blockhash not found")
                || lowered.contains("blockhashnotfound")
            let isBlockHeightExceeded = lowered.contains("block height exceeded")

            // Blockhash-not-found right after signing is usually propagation
            // lag: the RPC node we hit hasn't observed our (confirmed) blockhash
            // yet. Resending the same signed tx after a short backoff typically
            // clears it without escalating to a full keysign-ceremony retry.
            if isBlockhashNotFound, attempt < Self.maxBroadcastAttempts {
                logger.warning("solana broadcast attempt \(attempt)/\(Self.maxBroadcastAttempts) hit transient blockhash-not-found; resending after backoff")
                try await Task.sleep(for: broadcastRetryBackoff)
                continue
            }

            // "Block height exceeded" (or an exhausted blockhash-not-found
            // retry) means the blockhash has expired — resending the same tx
            // can't help, so surface it as retryable to re-sign with a fresh
            // blockhash.
            if isBlockhashNotFound || isBlockHeightExceeded {
                throw SolanaRetryableError.blockhashExpired(message: error.message)
            }

            // Surface the preflight program logs — on a simulation failure they
            // name the real on-chain reason (e.g. insufficient funds for rent,
            // exceeded compute budget) that the bare message omits.
            if let logs = error.data?.logs, !logs.isEmpty {
                logger.error("solana broadcast simulation failed: \(error.message, privacy: .public)\nlogs:\n\(logs.joined(separator: "\n"), privacy: .public)")
                throw SolanaServiceError.rpcError(
                    message: "\(error.message)\n\(logs.suffix(4).joined(separator: "\n"))",
                    code: error.code
                )
            }

            throw SolanaServiceError.rpcError(message: error.message, code: error.code)
        }

        // Unreachable: the loop either returns a result or throws on the final
        // attempt. Present to satisfy the non-optional control-flow analysis.
        return nil
    }

    func getSolanaBalance(coin: Coin) async throws -> String {
        try await getSolanaBalance(coin: coin.toCoinMeta(), address: coin.address)
    }

    func getSolanaBalance(coin: CoinMeta, address: String) async throws -> String {
        if coin.isNativeToken {
            let response = try await httpClient.request(
                api(.getBalance(address: address)),
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
            api(.getRecentPrioritizationFees),
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
            api(.getLatestBlockhash),
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
            api(.getTokenAccountsByOwner(walletAddress: walletAddress, filter: .mint(mintAddress))),
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
                    api(.getTokenAccountsByOwner(walletAddress: walletAddress, filter: .programId(program))),
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
            api(.getAccountInfo(address: address)),
            responseType: SolanaGetAccountInfoResponse.self
        )

        guard let value = response.data.result.value else {
            return (false, false)
        }

        let isToken2022 = value.owner == TOKEN_PROGRAM_ID_2022
        return (true, isToken2022)
    }

    // MARK: - Native staking reads

    /// Rent-exempt reserve for a 200-byte stake account. Rent params change
    /// rarely, so it is cached 24h via `Utils.getCachedData`.
    private var rentReserveCache = ThreadSafeDictionary<String, (data: UInt64, timestamp: Date)>()
    /// Live epoch info. Cached 45s so a screen refresh doesn't re-hit RPC on
    /// every appear while still tracking the ~2-day epoch closely.
    private var epochInfoCache = ThreadSafeDictionary<String, (data: SolanaEpochInfo, timestamp: Date)>()

    private static let rentReserveTTL: TimeInterval = 60 * 60 * 24
    private static let epochInfoTTL: TimeInterval = 45

    /// All validators (vote accounts), tagged with their delinquent bucket.
    func fetchSolanaValidators() async throws -> [SolanaValidator] {
        let response = try await httpClient.request(
            api(.getVoteAccounts),
            responseType: SolanaGetVoteAccountsResponse.self
        )
        let current = response.data.result.current.map { SolanaValidator(voteAccount: $0, isDelinquent: false) }
        let delinquent = response.data.result.delinquent.map { SolanaValidator(voteAccount: $0, isDelinquent: true) }
        return current + delinquent
    }

    /// Parsed stake accounts delegated by `owner` (the staker authority). Uses
    /// the `dataSize:200 + memcmp{offset:12}` filter and `jsonParsed` encoding.
    /// Not cached — must reflect a just-submitted stake/unstake and freshly
    /// accrued rewards; the UI refreshes on appear.
    func fetchSolanaStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] {
        let response = try await httpClient.request(
            api(.getStakeAccountsByOwner(staker: owner, pubkeyOnly: false)),
            responseType: SolanaGetProgramAccountsResponse.self
        )
        return response.data.result.compactMap { SolanaStakeAccount(programAccount: $0) }
    }

    /// Full parsed info for a single stake account.
    func fetchSolanaStakeAccount(address: String) async throws -> SolanaStakeAccount? {
        let response = try await httpClient.request(
            api(.getStakeAccountInfo(address: address)),
            responseType: SolanaGetStakeAccountInfoResponse.self
        )
        guard let value = response.data.result.value else { return nil }
        return SolanaStakeAccount(pubkey: address, accountInfo: value)
    }

    /// Current epoch info, cached 45s.
    func fetchSolanaEpochInfo() async throws -> SolanaEpochInfo {
        let cacheKey = "solana-epoch-info"
        if let cached: SolanaEpochInfo = Utils.getCachedData(cacheKey: cacheKey, cache: epochInfoCache, timeInSeconds: Self.epochInfoTTL) {
            return cached
        }
        let response = try await httpClient.request(
            api(.getEpochInfo),
            responseType: SolanaGetEpochInfoResponse.self
        )
        let info = response.data.result
        epochInfoCache.set(cacheKey, (data: info, timestamp: Date()))
        return info
    }

    /// Rent-exempt reserve (lamports) for a 200-byte stake account, cached 24h.
    func fetchSolanaRentReserve() async throws -> UInt64 {
        let cacheKey = "solana-rent-reserve-\(SolanaStakingConfig.stakeStateSize)"
        if let cached: UInt64 = Utils.getCachedData(cacheKey: cacheKey, cache: rentReserveCache, timeInSeconds: Self.rentReserveTTL) {
            return cached
        }
        let response = try await httpClient.request(
            api(.getMinimumBalanceForRentExemption(size: SolanaStakingConfig.stakeStateSize)),
            responseType: SolanaGetMinimumBalanceForRentExemptionResponse.self
        )
        let reserve = response.data.result
        rentReserveCache.set(cacheKey, (data: reserve, timestamp: Date()))
        return reserve
    }

    /// Drops the short-lived epoch-info cache so the next read reflects a freshly
    /// advanced epoch. Stake accounts are already uncached, so after a signed
    /// delegate/unstake/withdraw/move the only stale read is the 45 s epoch cache
    /// the activation/cooldown state is derived against; clear it so the post-tx
    /// row state is exact.
    func invalidateEpochInfoCache() {
        epochInfoCache.clear()
    }

    /// Network total inflation rate for the current epoch (fraction, e.g.
    /// 0.0377). Caching is owned by `SolanaStakingService` (10 min, actor).
    func fetchSolanaInflationRate() async throws -> Double {
        let response = try await httpClient.request(
            api(.getInflationRate),
            responseType: SolanaGetInflationRateResponse.self
        )
        return response.data.result.total
    }

}
