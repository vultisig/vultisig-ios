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

/// Outcome of a `simulateTransaction` dry run.
struct SolanaSimulationResult: Equatable {
    /// `nil` when the transaction executed cleanly. Otherwise the rendered
    /// `err`, e.g. `BlockhashNotFound` or `{InstructionError: [3, {Custom: 6003}]}`.
    let failure: String?
    let unitsConsumed: UInt64?
    let logs: [String]
    /// Lamports each requested account holds *after* the simulated transaction,
    /// keyed by address. Empty unless the caller asked for accounts, and an
    /// account the node reported as non-existent is absent rather than zero.
    let accountLamports: [String: UInt64]

    init(
        failure: String?,
        unitsConsumed: UInt64?,
        logs: [String],
        accountLamports: [String: UInt64] = [:]
    ) {
        self.failure = failure
        self.unitsConsumed = unitsConsumed
        self.logs = logs
        self.accountLamports = accountLamports
    }

    var succeeded: Bool { failure == nil }
}

/// The one read the pre-keysign blockhash refresh performs.
///
/// Its own protocol because that refresh is the last code to touch a payload
/// before its keysign messages are generated: what it does — and does not do —
/// to a raw transaction has to be assertable without a network.
protocol SolanaFinalizedBlockhashProviding {
    func fetchFinalizedBlockhash() async throws -> String?
}

class SolanaService: SolanaAddressLookupTableFetching, SolanaFinalizedBlockhashProviding {
    static let shared = SolanaService()

    private let logger = Log.chain.service
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

    /// How long a read of an Address Lookup Table stays usable. Injectable for
    /// the same reason `broadcastRetryBackoff` is: a test has to drive expiry
    /// without waiting out the real interval.
    private let addressLookupTableTTL: TimeInterval

    init(resolver: RPCEndpointResolving = CustomRPCStore.shared,
         httpClient: HTTPClientProtocol = HTTPClient(),
         broadcastRetryBackoff: Duration = .seconds(2),
         addressLookupTableTTL: TimeInterval = SolanaService.defaultAddressLookupTableTTL) {
        self.resolver = resolver
        self.httpClient = httpClient
        self.broadcastRetryBackoff = broadcastRetryBackoff
        self.addressLookupTableTTL = addressLookupTableTTL
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

    /// Dry-runs a transaction against the current bank. Returns the outcome
    /// rather than throwing on an on-chain failure — "this transaction would
    /// fail, and here is why" is a result the caller acts on, not a transport
    /// error. A JSON-RPC transport failure still throws.
    ///
    /// - Parameters:
    ///   - replaceRecentBlockhash: `true` lets the node substitute its own
    ///     blockhash, so a transaction can be checked before the pre-keysign
    ///     refresh gives it a live one. `false` simulates the exact bytes.
    ///   - accountAddresses: accounts whose post-execution lamports the caller
    ///     needs. Asking for the fee payer is how a transaction's real cost is
    ///     measured rather than estimated.
    func simulateTransaction(
        base64Transaction: String,
        replaceRecentBlockhash: Bool,
        accountAddresses: [String] = []
    ) async throws -> SolanaSimulationResult {
        let response = try await httpClient.request(
            api(.simulateTransaction(
                encodedTransaction: base64Transaction,
                replaceRecentBlockhash: replaceRecentBlockhash,
                accountAddresses: accountAddresses
            )),
            responseType: SolanaSimulateTransactionResponse.self
        )

        if let error = response.data.error {
            throw SolanaServiceError.rpcError(message: error.message, code: error.code)
        }
        guard let value = response.data.result?.value else {
            throw SolanaServiceError.rpcError(message: "simulateTransaction returned no result", code: -1)
        }

        let logs = value.logs ?? []
        if let failure = value.err {
            logger.warning(
                "solana simulation failed: \(failure.text, privacy: .public)\nlogs:\n\(logs.suffix(8).joined(separator: "\n"), privacy: .public)"
            )
        }

        return SolanaSimulationResult(
            failure: value.err?.text,
            unitsConsumed: value.unitsConsumed,
            logs: logs,
            accountLamports: Self.accountLamports(
                addresses: accountAddresses,
                accounts: value.accounts
            )
        )
    }

    /// Pairs the returned account states back to the addresses that were asked
    /// for. The RPC answers positionally, so a response of a different length is
    /// unusable rather than partially trusted — a mis-paired balance would be
    /// attributed to the wrong account.
    private static func accountLamports(
        addresses: [String],
        accounts: [SolanaSimulateTransactionResponse.Result.Value.Account?]?
    ) -> [String: UInt64] {
        guard !addresses.isEmpty, let accounts, accounts.count == addresses.count else { return [:] }
        var lamports: [String: UInt64] = [:]
        for (address, account) in zip(addresses, accounts) {
            guard let account else { continue }
            lamports[address] = account.lamports
        }
        return lamports
    }

    /// Address Lookup Table contents, keyed by table address. See
    /// `fetchAddressLookupTable(address:)` for why this is safe to cache and why
    /// the TTL is deliberately short.
    private var addressLookupTableCache = ThreadSafeDictionary<String, (data: [String], timestamp: Date)>()

    /// One minute. Long enough to serve a whole deposit — which prepares twice —
    /// off one read, short enough that a repointed table costs one bad attempt
    /// rather than a minute of them.
    static let defaultAddressLookupTableTTL: TimeInterval = 60

    /// Reads the contents of the given Address Lookup Tables, keyed by table
    /// address.
    ///
    /// A v0 transaction names most of its accounts by position inside a table, so
    /// nothing can say what such a transaction touches without these. Every
    /// requested table must resolve: a partial map would let an unverifiable
    /// account index be treated as absent.
    func fetchAddressLookupTables(addresses: [String]) async throws -> [String: [String]] {
        let unique = Array(Set(addresses))
        guard !unique.isEmpty else { return [:] }

        return try await withThrowingTaskGroup(of: (String, [String]).self) { group in
            for address in unique {
                group.addTask { (address, try await self.fetchAddressLookupTable(address: address)) }
            }
            var tables: [String: [String]] = [:]
            for try await (address, contents) in group {
                tables[address] = contents
            }
            return tables
        }
    }

    /// One table's contents, cached briefly.
    ///
    /// **Why caching is safe**, in three parts.
    ///
    /// *An entry never changes meaning.* The Address Lookup Table program can
    /// create, extend, freeze, deactivate and close a table — there is no
    /// instruction that overwrites an existing slot, and a closed table cannot
    /// come back at the same address, because the address is derived from the
    /// authority and a *recent* slot that cannot be reused. So on the canonical
    /// chain an index that resolved to some account keeps resolving to it, and
    /// the only way a cached copy differs is by being SHORT of entries appended
    /// since it was read.
    ///
    /// *A short copy is a refusal.* A v0 transaction naming an index the cached
    /// copy does not have refuses as `lookupIndexOutOfRange`, before any
    /// per-instruction check runs.
    ///
    /// *And nothing downstream trusts a table to say what an account IS.* A
    /// table only decides which pubkey an index NAMES; every account that
    /// decides where money goes is compared by `KaminoTransactionValidator`
    /// against a value the app derived locally — the fee payer, the registry's
    /// vault and its two mints, the derived associated-token accounts, the
    /// derived farm user state — and any writable account a builder-composed
    /// instruction touches must additionally be one of those. Contents that
    /// disagree with the chain therefore rename an account into a mismatch
    /// (`accountMismatch`, `unattributableWritableAccount`), not out of one.
    ///
    /// What that leaves is the case where the app resolves a table one way and
    /// the runtime later resolves it another — which needs an optimistically
    /// confirmed extension to be rolled back. That window is not created here:
    /// it already spans every read-to-execution gap, including the whole
    /// keysign ceremony, and the final `simulateTransaction` on the exact
    /// signed bytes resolves the lookups again on the node's own state. This
    /// TTL adds at most a minute to it.
    ///
    /// **Why the TTL is short.** Because the failure mode is a refusal, and a
    /// refusal lasts as long as the entry does. If Kamino ever repoints a vault
    /// at a table with new entries, a long TTL would keep deposits failing for
    /// the whole TTL after the chain had already moved on. A minute bounds that
    /// to something a user reads as one bad attempt, while still collapsing the
    /// two prepares a single deposit runs — the reserve probe and the real build
    /// — into one read.
    func fetchAddressLookupTable(address: String) async throws -> [String] {
        let target = api(.getAddressLookupTable(address: address))
        // Namespaced by the endpoint the read would have gone to, not by the
        // table address alone. A table address means whatever the cluster
        // answering for it says it means, the custom-RPC override is resolved
        // per request, and `SolanaService.shared` outlives a change to it — so
        // an entry read from one endpoint must never answer for another.
        let cacheKey = "solana-address-lookup-table-\(HTTPClient.url(for: target).absoluteString)|\(address)"
        if let cached: [String] = Utils.getCachedData(
            cacheKey: cacheKey,
            cache: addressLookupTableCache,
            timeInSeconds: addressLookupTableTTL
        ) {
            return cached
        }

        let response = try await httpClient.request(
            target,
            responseType: SolanaGetAccountInfoBase64Response.self
        )
        guard let value = response.data.result.value else {
            throw SolanaAddressLookupTableError.accountNotFound(address)
        }
        let addresses = try SolanaAddressLookupTable.addresses(
            table: address,
            owner: value.owner,
            data: value.data
        )
        addressLookupTableCache.set(cacheKey, (data: addresses, timestamp: Date()))
        return addresses
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
        try await fetchPrioritizationFeeSample() ?? SolanaHelper.defaultPriorityFeePrice
    }

    /// Median of the recent non-zero prioritization fees, or `nil` when the
    /// network reported none.
    ///
    /// The distinction matters: "nobody is paying a priority fee" and "the
    /// median is X" are different answers, and a caller with its own floor needs
    /// to apply that floor rather than inherit this file's generic default —
    /// which is 1,000,000 µlamports and would be a fifty-fold over-tip for a
    /// caller whose own fallback is 20,000.
    func fetchPrioritizationFeeSample() async throws -> UInt64? {
        let response = try await httpClient.request(
            api(.getRecentPrioritizationFees),
            responseType: SolanaGetRecentPrioritizationFeesResponse.self
        )

        let nonZeroFees = response.data.result
            .map { $0.prioritizationFee }
            .filter { $0 > 0 }
            .sorted()

        guard !nonZeroFees.isEmpty else {
            return nil
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

    /// `finalized`-commitment blockhash for the pre-keysign refresh. A confirmed
    /// blockhash can be unknown to the load-balanced proxy's broadcast node
    /// (preflight `BlockhashNotFound`); a finalized one is rooted and known to
    /// every node.
    func fetchFinalizedBlockhash() async throws -> String? {
        let response = try await httpClient.request(
            api(.getLatestBlockhashFinalized),
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
            logger.error("Error in fetchSolanaTokenInfoList:")
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
                logger.warning("Error in fetchSolanaJupiterTokenInfoList: Rate limit exceeded (429)")
            } else {
                logger.error("Error in fetchSolanaJupiterTokenInfoList: \(error.localizedDescription, privacy: .public) (Code: \(error.code))")
            }
            throw error
        } catch {
            logger.error("Error in fetchSolanaJupiterTokenInfoList: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func fetchSolanaJupiterTokenList() async throws -> [CoinMeta] {
        do {
            let urlString = Endpoint.solanaTokenInfoList()
            let dataResponse = try await Utils.asyncGetRequest(
                urlString: urlString, headers: [:])

            // Decoded, ranked best-first and mapped in one place: `CoinMeta`
            // carries no score, so ordering is the only channel Jupiter's quality
            // signal has to reach the catalog.
            return try SolanaJupiterToken.rankedCatalogMetas(from: dataResponse)
        } catch let error as NSError {
            if error.code == 429 {
                logger.warning("Error in fetchSolanaJupiterTokenList: Rate limit exceeded (429)")
            } else {
                logger.error("Error in fetchSolanaJupiterTokenList: \(error.localizedDescription, privacy: .public) (Code: \(error.code))")
            }
            throw error
        } catch {
            logger.error("Error in fetchSolanaJupiterTokenList: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func fetchTokenAssociatedAccountByOwner(for ownerAddress: String, mintAddress: String) async throws -> (String, Bool) {
        // First try getTokenAccountsByOwner. A transient RPC/node error is treated
        // like an empty result: the account index can lag right after an ATA is
        // created, or the node may momentarily fail, yet the ATA is still
        // deterministically derivable. Falling through to the derivation probe
        // instead of propagating keeps the send from failing when the account
        // actually exists. A successful lookup keeps today's behavior exactly.
        do {
            let (tokenAccounts, isToken2022) = try await getTokenAccountsByOwner(walletAddress: ownerAddress, mintAddress: mintAddress)

            if !tokenAccounts.isEmpty {
                return (tokenAccounts, isToken2022)
            }
        } catch {
            logger.warning("getTokenAccountsByOwner lookup failed; falling back to ATA derivation: \(error.localizedDescription, privacy: .public)")
        }

        // If getTokenAccountsByOwner returns empty (or errored), probe the deterministic ATAs directly
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
            logger.error("Error in fetchTokenBalance: \(error.localizedDescription, privacy: .public)")
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
            logger.error("Error in fetchTokens: \(error.localizedDescription, privacy: .public)")
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
    /// Network minimum active delegation (lamports). Changes only on a rare
    /// feature-gate activation, so it is cached 24h like the rent reserve.
    private var minDelegationCache = ThreadSafeDictionary<String, (data: UInt64, timestamp: Date)>()

    private static let rentReserveTTL: TimeInterval = 60 * 60 * 24
    private static let epochInfoTTL: TimeInterval = 45
    private static let minDelegationTTL: TimeInterval = 60 * 60 * 24

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
        try await fetchRentExemptMinimum(size: SolanaStakingConfig.stakeStateSize)
    }

    /// Rent-exempt reserve (lamports) for an account of `size` data bytes,
    /// cached 24h per size.
    ///
    /// `size: 0` is the floor a plain wallet account has to stay above: an
    /// account that a transaction modifies and leaves with a non-zero balance
    /// below its rent-exempt minimum is rejected on-chain
    /// (`InsufficientFundsForRent`), so a "max" that spends into that band would
    /// build a transaction that cannot execute.
    func fetchRentExemptMinimum(size: Int) async throws -> UInt64 {
        let cacheKey = "solana-rent-reserve-\(size)"
        if let cached: UInt64 = Utils.getCachedData(cacheKey: cacheKey, cache: rentReserveCache, timeInSeconds: Self.rentReserveTTL) {
            return cached
        }
        let response = try await httpClient.request(
            api(.getMinimumBalanceForRentExemption(size: size)),
            responseType: SolanaGetMinimumBalanceForRentExemptionResponse.self
        )
        let reserve = response.data.result
        rentReserveCache.set(cacheKey, (data: reserve, timestamp: Date()))
        return reserve
    }

    /// Network minimum active delegation (lamports), cached 24h. The Vultisig
    /// proxy blocks `getStakeMinimumDelegation`, so this reads directly from a
    /// public node (PublicNode, then mainnet-beta as fallback). The value is a
    /// network-global constant used only as a form-validation floor and never
    /// touches signing, so the off-proxy read is safe. Throws when every public
    /// host fails; the caller falls back to the documented
    /// `SolanaStakingConfig.minDelegationFloorLamports`.
    func fetchSolanaMinDelegation() async throws -> UInt64 {
        let cacheKey = "solana-min-delegation"
        if let cached: UInt64 = Utils.getCachedData(cacheKey: cacheKey, cache: minDelegationCache, timeInSeconds: Self.minDelegationTTL) {
            return cached
        }
        var lastError: Error?
        for host in SolanaAPI.minDelegationPublicHosts {
            do {
                let response = try await httpClient.request(
                    SolanaAPI(baseURL: host, usesProxyPath: false, rpcMethod: .getStakeMinimumDelegation),
                    responseType: SolanaGetStakeMinimumDelegationResponse.self
                )
                let minimum = response.data.result.value
                minDelegationCache.set(cacheKey, (data: minimum, timestamp: Date()))
                return minimum
            } catch {
                lastError = error
                logger.warning("getStakeMinimumDelegation failed on \(host.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        throw lastError ?? SolanaServiceError.rpcError(message: "getStakeMinimumDelegation: no public host responded", code: -1)
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
