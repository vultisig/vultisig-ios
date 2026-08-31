//
//  TronService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/01/25.
//

import Foundation
import BigInt
import WalletCore

class TronService {

    private struct FeeEstimate {
        let displayFee: BigInt
        let feeLimit: BigInt
    }

    static let shared = TronService()

    private let apiService: TronAPIService

    // Cache for chain parameters
    private var chainParametersCache: TronChainParametersResponse?

    /// Per-address TTL cache for account + resource responses, shared across
    /// the DeFi screens so re-opening paints instantly instead of refetching.
    private let accountCache = TronAccountCache()

    /// Time-to-live for cached account/resource data, in seconds. Tunable —
    /// short enough that balances stay fresh after a freeze/unfreeze, long
    /// enough that navigating back into the screen serves from cache.
    static var accountCacheTTL: TimeInterval = 60

    // Constants from Android implementation
    private static let BYTES_PER_COIN_TX: Int64 = 300
    private static let BYTES_PER_CONTRACT_TX: Int64 = 345

    /// Headroom multiplier applied to the simulated `energy_used` when
    /// computing the on-chain `fee_limit` cap. The margin covers ordinary
    /// drift between simulation and broadcast; the max-factor fallback below
    /// handles cases where simulation is unavailable. See
    /// https://developers.tron.network/docs/resource-model#dynamic-energy-model.
    private static let ENERGY_SAFETY_NUMERATOR: Int64 = 13
    private static let ENERGY_SAFETY_DENOMINATOR: Int64 = 10

    /// Base-energy estimate for a common high-volume TRC20 transfer. When
    /// simulation is unavailable, this is multiplied by the chain's maximum
    /// Dynamic Energy factor instead of sharing the much smaller opaque-swap
    /// estimate below.
    private static let DEFAULT_TRC20_BASE_ENERGY_USED: Int64 = 65_000
    private static let DYNAMIC_ENERGY_FACTOR_SCALE: Int64 = 10_000

    /// Energy estimate used for an opaque native-TRX contract swap when the
    /// transaction bytes have not reached the fee layer yet.
    /// At 420 sun/energy this works out to 21 TRX; at the current 100-sun
    /// fallback price it is 5 TRX. This is a spending cap, not an upfront
    /// charge; successful calls consume only the resources they use.
    private static let DEFAULT_MAX_ENERGY_USED: Int64 = 50_000

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.apiService = TronAPIService(httpClient: httpClient)
    }

    // MARK: - Broadcast

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        do {
            let txHash = try await apiService.broadcastTransaction(jsonString: jsonString)
            return .success(txHash)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Block Info

    func getBlockInfo(
        coin: Coin,
        to: String? = nil,
        memo: String? = nil,
        isSwap: Bool = false
    ) async throws -> BlockChainSpecific {
        let response = try await apiService.getNowBlock()

        let currentTimestampMillis = UInt64(Date().timeIntervalSince1970 * 1000)
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let oneHourMillis = Int64(60 * 60 * 1000)
        let expiration = nowMillis + oneHourMillis

        let estimate = try await calculateTronFee(coin: coin, to: to, memo: memo, isSwap: isSwap)

        return BlockChainSpecific.Tron(
            timestamp: currentTimestampMillis,
            expiration: UInt64(expiration),
            blockHeaderTimestamp: response.block_header?.raw_data?.timestamp ?? 0,
            blockHeaderNumber: response.block_header?.raw_data?.number ?? 0,
            blockHeaderVersion: UInt64(response.block_header?.raw_data?.version ?? 0),
            blockHeaderTxTrieRoot: response.block_header?.raw_data?.txTrieRoot ?? "",
            blockHeaderParentHash: response.block_header?.raw_data?.parentHash ?? "",
            blockHeaderWitnessAddress: response.block_header?.raw_data?.witness_address ?? "",
            gasFeeEstimation: UInt64(estimate.displayFee.description) ?? 0,
            feeLimit: UInt64(estimate.feeLimit.description) ?? 0
        )
    }

    // MARK: - Token Info

    func getTokenInfo(contractAddress: String) async throws -> (name: String, symbol: String, decimals: Int) {
        return try await apiService.getTokenInfo(contractAddress: contractAddress)
    }

    // MARK: - Balance

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        if coin.isNativeToken {
            return try await apiService.getNativeBalance(address: address)
        } else {
            let balance = try await apiService.getTRC20Balance(
                contractAddress: coin.contractAddress,
                walletAddress: address
            )
            return String(balance)
        }
    }

    // MARK: - Account Info

    /// Returns the account for `address`, served from the TTL cache when a
    /// fresh entry exists. `forceRefresh` bypasses the cache for explicit
    /// pull-to-refresh. Concurrent callers for the same address coalesce onto
    /// a single network request.
    func getAccount(address: String, forceRefresh: Bool = false) async throws -> TronAccountResponse {
        try await accountCache.account(for: address, forceRefresh: forceRefresh) {
            try await self.apiService.getAccount(address: address)
        }
    }

    /// Returns the account resources for `address`, served from the TTL cache
    /// when fresh. See `getAccount(address:forceRefresh:)` for cache semantics.
    func getAccountResource(address: String, forceRefresh: Bool = false) async throws -> TronAccountResourceResponse {
        try await accountCache.resource(for: address, forceRefresh: forceRefresh) {
            try await self.apiService.getAccountResource(address: address)
        }
    }

    /// Returns the cached account for `address` only if a non-expired entry
    /// exists, without touching the network. Lets a screen paint instantly
    /// (no spinner) when data is fresh and fall back to a network load only
    /// when the cache is cold or stale.
    func cachedAccount(for address: String) async -> TronAccountResponse? {
        await accountCache.cachedAccount(for: address)
    }

    /// Cached-resource counterpart to `cachedAccount(for:)`.
    func cachedAccountResource(for address: String) async -> TronAccountResourceResponse? {
        await accountCache.cachedResource(for: address)
    }

    /// Drops any cached account + resource entry for `address` so the next
    /// load refetches. Called after a freeze/unfreeze so balances update when
    /// the user navigates back into the DeFi screens.
    func invalidateAccountCache(for address: String) async {
        await accountCache.invalidate(address: address)
    }

    // MARK: - Private Helpers

    /// Returns both the user-visible fee estimate and the gross ceiling written
    /// as `$0.feeLimit` on contract paths.
    ///
    /// **Native TRX transfer** — bandwidth-only fee. Signing path doesn't
    /// write `$0.feeLimit` for plain `transfer` contracts, so this number
    /// only drives the UI.
    ///
    /// **TRC20 transfer** — simulate the call via
    /// `triggerConstantContract` to get a per-tx `energy_used`, apply a
    /// safety multiplier, translate to sun via the on-chain `energyFeePrice`.
    /// Replaces the prior fixed 1 TRX / 18 TRX / 36 TRX ladder that
    /// triggered `OUT_OF_ENERGY` whenever the actual energy cost exceeded
    /// `fee_limit / energy_price`.
    ///
    /// **Opaque native swap** — pre-built transaction bytes arrive after this
    /// layer and cannot be simulated from the `isSwap` flag alone, so use the
    /// smaller UI estimate (`DEFAULT_MAX_ENERGY_USED × energyFeePrice`).
    ///
    /// See https://developers.tron.network/docs/set-feelimit.
    private func calculateTronFee(
        coin: Coin,
        to: String?,
        memo: String?,
        isSwap: Bool
    ) async throws -> FeeEstimate {
        let memoFee = (try? await getTronFeeMemo(memo: memo)) ?? .zero
        let activationFee = (try? await getTronInactiveDestinationFee(to: to)) ?? .zero
        let chainParams = try? await getCachedChainParameters()
        let energyPrice = chainParams?.energyFeePrice ?? TronChainParametersResponse.defaultEnergyFeePrice
        let dynamicEnergyMaxFactor = chainParams?.dynamicEnergyMaxFactor
            ?? TronChainParametersResponse.defaultDynamicEnergyMaxFactor
        let maxFeeLimit = chainParams?.maxFeeLimit ?? TronChainParametersResponse.defaultMaxFeeLimit

        let transactionEstimate: FeeEstimate
        if coin.isNativeToken {
            if isSwap {
                let feeLimit = Self.cappedFeeLimit(
                    Self.defaultContractFeeLimit(energyPrice: energyPrice),
                    maxFeeLimit: maxFeeLimit
                )
                transactionEstimate = FeeEstimate(displayFee: feeLimit, feeLimit: feeLimit)
            } else {
                // A *successfully computed* 0 means sufficient bandwidth — a
                // genuinely free transfer, surfaced as 0. But a thrown error
                // (transient account-resource / chain-parameter fetch failure)
                // is indistinguishable from that once collapsed to `.zero`,
                // which would render a real transfer as falsely free. Fall back
                // to the coin's conservative static fee only on that error path.
                let fee = (try? await calculateNativeTrxFee(coin: coin)) ?? coin.feeDefault.toBigInt()
                transactionEstimate = FeeEstimate(displayFee: fee, feeLimit: fee)
            }
        } else {
            transactionEstimate = await calculateTrc20Fee(
                coin: coin,
                to: to,
                energyPrice: energyPrice,
                dynamicEnergyMaxFactor: dynamicEnergyMaxFactor,
                maxFeeLimit: maxFeeLimit
            )
        }

        let displayFee = transactionEstimate.displayFee + memoFee + activationFee
        let feeLimit = transactionEstimate.feeLimit + memoFee + activationFee
        if isSwap || !coin.isNativeToken {
            return FeeEstimate(
                displayFee: Self.cappedFeeLimit(displayFee, maxFeeLimit: maxFeeLimit),
                feeLimit: Self.cappedFeeLimit(feeLimit, maxFeeLimit: maxFeeLimit)
            )
        }
        return FeeEstimate(displayFee: displayFee, feeLimit: feeLimit)
    }

    private func calculateNativeTrxFee(coin: Coin) async throws -> BigInt {
        let accountResource = try await apiService.getAccountResource(address: coin.address)
        let availableBandwidth = accountResource.calculateAvailableBandwidth()
        return try await getBandwidthFeeDiscount(
            isNativeToken: true,
            availableBandwidth: availableBandwidth
        )
    }

    private func calculateTrc20Fee(
        coin: Coin,
        to: String?,
        energyPrice: Int64,
        dynamicEnergyMaxFactor: Int64,
        maxFeeLimit: Int64
    ) async -> FeeEstimate {
        let fallback = Self.defaultTrc20FeeLimit(
            energyPrice: energyPrice,
            dynamicEnergyMaxFactor: dynamicEnergyMaxFactor,
            maxFeeLimit: maxFeeLimit
        )
        let fallbackEstimate = FeeEstimate(displayFee: fallback, feeLimit: fallback)
        guard let to, !to.isEmpty, !coin.contractAddress.isEmpty else {
            return fallbackEstimate
        }

        let simulation: TronTriggerConstantResponse
        do {
            simulation = try await apiService.simulateTRC20Transfer(
                ownerAddress: coin.address,
                contractAddress: coin.contractAddress,
                toAddress: to
            )
        } catch {
            return fallbackEstimate
        }

        let simulationMessage = simulation.result?.message?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard simulation.result?.result == true, simulationMessage.isEmpty,
              let energyUsed = simulation.energy_used,
              let totalEnergyUsed = Self.simulatedTotalEnergy(
                energyUsed: energyUsed,
                energyPenalty: simulation.energy_penalty
              ) else {
            return fallbackEstimate
        }

        let availableEnergy: Int64
        do {
            let accountResource = try await apiService.getAccountResource(address: coin.address)
            availableEnergy = accountResource.calculateAvailableEnergy()
        } catch {
            // Unknown resources must never turn into a misleading zero-fee
            // estimate. Assuming no staked Energy shows the full simulated burn
            // while leaving the independently-computed signed ceiling intact.
            availableEnergy = 0
        }

        let feeLimit = Self.cappedFeeLimit(
            Self.contractFeeLimit(energyUsed: totalEnergyUsed, energyPrice: energyPrice),
            maxFeeLimit: maxFeeLimit
        )
        let displayFee = Self.cappedFeeLimit(
            Self.trc20DisplayFee(
                totalEnergyUsed: totalEnergyUsed,
                availableEnergy: availableEnergy,
                energyPrice: energyPrice
            ),
            maxFeeLimit: maxFeeLimit
        )
        return FeeEstimate(displayFee: displayFee, feeLimit: feeLimit)
    }

    /// Opaque native-swap estimate. TRC20 simulation failures deliberately use
    /// the larger max-factor budget below so this 50,000-energy value is never
    /// written as a TRC20 `fee_limit`.
    static func defaultContractFeeLimit(energyPrice: Int64) -> BigInt {
        BigInt(DEFAULT_MAX_ENERGY_USED) * BigInt(energyPrice)
    }

    /// Simulation-error budget for TRC20 transfers. TRON documents the
    /// maximum Dynamic Energy factor as an additional multiplier scaled by
    /// 10,000, so the total ceiling is `base × (1 + maxFactor)`.
    static func defaultTrc20FeeLimit(
        energyPrice: Int64,
        dynamicEnergyMaxFactor: Int64,
        maxFeeLimit: Int64
    ) -> BigInt {
        let safeMaxFactor = max(dynamicEnergyMaxFactor, 0)
        let maxEnergyUnits = BigInt(DEFAULT_TRC20_BASE_ENERGY_USED)
            * (BigInt(DYNAMIC_ENERGY_FACTOR_SCALE) + BigInt(safeMaxFactor))
            / BigInt(DYNAMIC_ENERGY_FACTOR_SCALE)
        return cappedFeeLimit(maxEnergyUnits * BigInt(energyPrice), maxFeeLimit: maxFeeLimit)
    }

    static func cappedFeeLimit(_ feeLimit: BigInt, maxFeeLimit: Int64) -> BigInt {
        min(max(feeLimit, .zero), BigInt(max(maxFeeLimit, 0)))
    }

    /// `triggerconstantcontract.energy_used` is already the total Energy, and
    /// `energy_penalty` is the Dynamic Energy portion inside that total. Rebuild
    /// the total from base + penalty to make that relationship explicit and to
    /// reject malformed responses where the reported subset exceeds the total.
    /// See https://developers.tron.network/docs/set-feelimit#estimating-energy-before-broadcasting.
    static func simulatedTotalEnergy(energyUsed: Int, energyPenalty: Int?) -> Int64? {
        guard let total = Int64(exactly: energyUsed), total > 0 else { return nil }
        guard let penalty = Int64(exactly: energyPenalty ?? 0), penalty >= 0, penalty <= total else {
            return nil
        }
        let baseEnergy = total - penalty
        return baseEnergy + penalty
    }

    /// Estimated TRX burn after applying the sender's currently available
    /// staked Energy. This value is display-only; it never lowers `fee_limit`.
    static func trc20DisplayFee(
        totalEnergyUsed: Int64,
        availableEnergy: Int64,
        energyPrice: Int64
    ) -> BigInt {
        let energyToBurn = max(BigInt(totalEnergyUsed) - BigInt(max(availableEnergy, 0)), .zero)
        return energyToBurn * BigInt(max(energyPrice, 0))
    }

    /// Translates a simulated `energy_used` into a `fee_limit` cap (in sun),
    /// applying a 30% margin against estimate drift. Pulled out so the math
    /// is testable in isolation. All
    /// multiplications are performed in `BigInt` so an unexpectedly large
    /// `energy_used` or `energyPrice` can't overflow `Int64` mid-calculation.
    static func contractFeeLimit(energyUsed: Int64, energyPrice: Int64) -> BigInt {
        let maxEnergyUnits = (BigInt(energyUsed) * BigInt(ENERGY_SAFETY_NUMERATOR)) / BigInt(ENERGY_SAFETY_DENOMINATOR)
        return maxEnergyUnits * BigInt(energyPrice)
    }

    private func getCachedChainParameters() async throws -> TronChainParametersResponse {
        if let cached = chainParametersCache {
            return cached
        }

        let parameters = try await apiService.getChainParameters()
        chainParametersCache = parameters
        return parameters
    }

    private func getBandwidthFeeDiscount(isNativeToken: Bool, availableBandwidth: Int64) async throws -> BigInt {
        let feeBandwidthRequired = isNativeToken ? Self.BYTES_PER_COIN_TX : Self.BYTES_PER_CONTRACT_TX
        let chainParams = try await getCachedChainParameters()
        let bandwidthPrice = chainParams.bandwidthFeePrice

        switch (isNativeToken, availableBandwidth >= feeBandwidthRequired) {
        case (true, true):
            // Native transfer with sufficient bandwidth => FREE tx
            return BigInt.zero
        case (false, _):
            // TRC20 always pays fee (no free bandwidth for smart contracts)
            return BigInt(feeBandwidthRequired * bandwidthPrice)
        case (true, false):
            // Native transfer without sufficient bandwidth
            return BigInt(feeBandwidthRequired * bandwidthPrice)
        }
    }

    private func getTronFeeMemo(memo: String?) async throws -> BigInt {
        guard let memo = memo, !memo.isEmpty else {
            return BigInt.zero
        }

        // This marker selects a local WalletCore system-contract builder; it
        // is deliberately omitted from the transaction's `data` field. A TRON
        // memo fee is charged only for data that actually reaches the wire, so
        // adding getMemoFee here would show a fee the claim cannot incur.
        guard memo != TronHelper.withdrawExpireUnfreezeMemo else {
            return BigInt.zero
        }

        let chainParams = try await getCachedChainParameters()
        return BigInt(chainParams.memoFeeEstimate)
    }

    private func getTronInactiveDestinationFee(to: String?) async throws -> BigInt {
        guard let to = to, !to.isEmpty else {
            return BigInt.zero
        }

        let accountExists: Bool
        do {
            let account = try await apiService.getAccount(address: to)
            accountExists = !account.address.isEmpty
        } catch {
            accountExists = false
        }

        if accountExists {
            return BigInt.zero
        }

        let chainParams = try await getCachedChainParameters()
        let createAccountFee = BigInt(chainParams.createAccountFeeEstimate)
        let createAccountContractFee = BigInt(chainParams.createNewAccountFeeEstimateContract)

        return createAccountFee + createAccountContractFee
    }
}

// MARK: - Account Cache

/// Concurrency-safe, per-address TTL cache for TRON account + resource
/// responses, mirroring `THORChainAPICache`. Coalesces concurrent loads for
/// the same address onto a single in-flight request so the dashboard and the
/// resources loader opening together don't duplicate network calls.
private actor TronAccountCache {

    private struct CacheEntry<T> {
        let value: T
        let timestamp: Date

        func isExpired(duration: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) > duration
        }
    }

    private var accounts: [String: CacheEntry<TronAccountResponse>] = [:]
    private var resources: [String: CacheEntry<TronAccountResourceResponse>] = [:]
    private var inFlightAccounts: [String: Task<TronAccountResponse, Error>] = [:]
    private var inFlightResources: [String: Task<TronAccountResourceResponse, Error>] = [:]

    // MARK: Account

    func cachedAccount(for address: String) -> TronAccountResponse? {
        guard let entry = accounts[address],
              !entry.isExpired(duration: TronService.accountCacheTTL) else {
            return nil
        }
        return entry.value
    }

    func account(
        for address: String,
        forceRefresh: Bool,
        fetch: @escaping () async throws -> TronAccountResponse
    ) async throws -> TronAccountResponse {
        if !forceRefresh, let cached = cachedAccount(for: address) {
            return cached
        }

        if let existing = inFlightAccounts[address] {
            return try await existing.value
        }

        let task = Task { try await fetch() }
        inFlightAccounts[address] = task
        defer { inFlightAccounts[address] = nil }

        let value = try await task.value
        accounts[address] = CacheEntry(value: value, timestamp: Date())
        return value
    }

    // MARK: Resource

    func cachedResource(for address: String) -> TronAccountResourceResponse? {
        guard let entry = resources[address],
              !entry.isExpired(duration: TronService.accountCacheTTL) else {
            return nil
        }
        return entry.value
    }

    func resource(
        for address: String,
        forceRefresh: Bool,
        fetch: @escaping () async throws -> TronAccountResourceResponse
    ) async throws -> TronAccountResourceResponse {
        if !forceRefresh, let cached = cachedResource(for: address) {
            return cached
        }

        if let existing = inFlightResources[address] {
            return try await existing.value
        }

        let task = Task { try await fetch() }
        inFlightResources[address] = task
        defer { inFlightResources[address] = nil }

        let value = try await task.value
        resources[address] = CacheEntry(value: value, timestamp: Date())
        return value
    }

    // MARK: Invalidation

    func invalidate(address: String) {
        accounts[address] = nil
        resources[address] = nil
    }
}
