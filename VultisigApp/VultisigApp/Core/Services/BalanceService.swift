//
//  BalanceService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.04.2024.
//

import Foundation
import OSLog
import SwiftData
import BigInt

class BalanceService {

    static let shared = BalanceService()
    private let logger = Logger(subsystem: "com.vultisig.app", category: "balance-service")

    private let utxo = BlockchairService.shared
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let maya = MayachainService.shared
    private let dot = PolkadotService.shared
    private let tao = BittensorService.shared
    private let ton = TonService.shared
    private let ripple = RippleService.shared
    private let tron = TronService.shared
    private let cardano = CardanoService.shared

    private let thorchainAPIService = THORChainAPIService()
    private let mayaChainAPIService = MayaChainAPIService()

    private let cryptoPriceService: CryptoPriceServiceProtocol

    init(cryptoPriceService: CryptoPriceServiceProtocol = CryptoPriceService.shared) {
        self.cryptoPriceService = cryptoPriceService
    }

    /// Cache of whether a chain's Multicall3 contract was verified to have code.
    /// Probed at most once per process for chains that need a runtime gate.
    private var multicallCodeVerified: [Chain: Bool] = [:]
    private var multicallCodeLock = os_unfair_lock()

    /// Key for grouping EVM coins so each (chain, wallet) issues one Multicall3 call.
    private struct EvmBatchKey: Hashable {
        let chain: Chain
        let address: String
    }

    /// Value type to identify a coin for balance fetching without holding SwiftData model references
    /// Reuses CoinMeta and adds only the minimal additional fields needed for balance operations
    private struct CoinIdentifier: Hashable {
        let coinId: String
        let coinMeta: CoinMeta
        let address: String

        init(from coin: Coin) {
            self.coinId = coin.id
            self.coinMeta = coin.toCoinMeta()
            self.address = coin.address
        }

        // Convenience accessors for commonly used CoinMeta properties
        var chain: Chain { coinMeta.chain }
        var ticker: String { coinMeta.ticker }
        var isNativeToken: Bool { coinMeta.isNativeToken }
    }

    /// Value type containing balance update data for a specific coin
    private struct CoinBalanceUpdate {
        let coinId: String
        let rawBalance: String?
        let stakedBalance: String?
        let bondedNodes: [RuneBondNode]?
        let error: Error?

        var hasUpdates: Bool {
            rawBalance != nil || stakedBalance != nil || bondedNodes != nil
        }
    }

    func updateBalances(vault: Vault) async {
        // Phase 1: Extract value-type identifiers on MainActor
        let coinIdentifiers = await extractCoinIdentifiers(from: vault)
        let coinMetas = coinIdentifiers.map { $0.coinMeta }

        // Prices and balances run concurrently. Balances never read prices (fiat
        // is computed lazily from RateProvider at render time), so a slow or
        // failing price provider must not gate balance freshness.
        async let pricesDone: Void = fetchRatesSafely(coins: coinMetas)
        let updates = await fetchBalanceUpdates(for: coinIdentifiers)

        // Phase 3: Apply updates in batch on MainActor (triggers SwiftUI updates).
        do {
            try await applyBalanceUpdates(updates, to: vault)
        } catch {
            logger.error("Update Balances error: \(error.localizedDescription)")
        }

        // Ensure rates have landed, then relabel fiat on MainActor.
        await pricesDone
        await refreshFiat(vault: vault)

        // Phase 4: Discover Cardano native tokens silently — mirrors Windows
        // CoinFinder behaviour. Failures here must never break a balance refresh.
        await discoverCardanoNativeTokens(vault: vault)
    }

    /// Rates-only refresh used when only the display currency changed. Fetches
    /// price rates and relabels fiat without issuing any per-coin balance RPCs or
    /// running Cardano token discovery.
    func refreshRates(vault: Vault) async {
        let metas = await extractCoinIdentifiers(from: vault).map { $0.coinMeta }
        await fetchRatesSafely(coins: metas)
        await refreshFiat(vault: vault)
    }

    /// Fetch price rates for the given coins, swallowing cancellation and logging
    /// other failures so a price outage can never gate balances.
    private func fetchRatesSafely(coins: [CoinMeta]) async {
        do {
            try await cryptoPriceService.fetchPrices(coins: coins)
        } catch {
            if (error as? URLError)?.code != .cancelled {
                logger.warning("Fetch Rates error: \(error.localizedDescription)")
            }
        }
    }

    /// Nudge SwiftUI to recompute fiat labels for the vault and its coins once
    /// fresh rates are cached. Balances are applied separately.
    @MainActor
    private func refreshFiat(vault: Vault) {
        vault.objectWillChange.send()
        for coin in vault.coins {
            coin.objectWillChange.send()
        }
    }

    /// Phase 1: Extract coin identifiers on MainActor
    @MainActor
    private func extractCoinIdentifiers(from vault: Vault) -> [CoinIdentifier] {
        return vault.coins.map { CoinIdentifier(from: $0) }
    }

    /// Phase 2: Fetch balance updates concurrently using identifiers.
    ///
    /// EVM coins on a chain with a verified Multicall3 deployment are grouped by
    /// (chain, wallet) and fetched in a single `aggregate3` call (native + every
    /// token in one round-trip). Everything else — non-EVM chains and EVM chains
    /// without a Multicall3 address — keeps the one-task-per-coin path verbatim.
    private func fetchBalanceUpdates(for identifiers: [CoinIdentifier]) async -> [CoinBalanceUpdate] {
        var batchGroups: [EvmBatchKey: [CoinIdentifier]] = [:]
        var perCoin: [CoinIdentifier] = []

        for identifier in identifiers {
            if identifier.chain.chainType == .EVM, Multicall3.address(for: identifier.chain) != nil {
                batchGroups[EvmBatchKey(chain: identifier.chain, address: identifier.address), default: []].append(identifier)
            } else {
                perCoin.append(identifier)
            }
        }

        return await withTaskGroup(of: [CoinBalanceUpdate].self) { group in
            var updates: [CoinBalanceUpdate] = []
            updates.reserveCapacity(identifiers.count)

            for (key, coins) in batchGroups {
                group.addTask { [weak self] in
                    guard let self, !Task.isCancelled else {
                        return coins.map { Self.emptyUpdate(for: $0) }
                    }
                    return await self.fetchEvmBatchBalances(chain: key.chain, address: key.address, coins: coins)
                }
            }

            for identifier in perCoin {
                group.addTask { [weak self] in
                    guard let self, !Task.isCancelled else {
                        return [Self.emptyUpdate(for: identifier)]
                    }
                    return [await self.fetchBalanceUpdate(for: identifier)]
                }
            }

            for await groupUpdates in group {
                updates.append(contentsOf: groupUpdates)
            }

            return updates
        }
    }

    private static func emptyUpdate(for identifier: CoinIdentifier) -> CoinBalanceUpdate {
        CoinBalanceUpdate(coinId: identifier.coinId, rawBalance: nil, stakedBalance: nil, bondedNodes: nil, error: nil)
    }

    /// Fetch every balance for one (chain, wallet) EVM group in a single
    /// Multicall3 call. On any thrown error (network blip, unexpected decode, or
    /// a failed runtime gate) the whole group degrades to the per-coin path, so a
    /// batch failure never zeroes balances — it just reverts to today's behaviour.
    /// EVM chains carry no staked/bonded balances, so the batch produces only
    /// `rawBalance`, identical to the per-coin path.
    private func fetchEvmBatchBalances(chain: Chain, address: String, coins: [CoinIdentifier]) async -> [CoinBalanceUpdate] {
        guard let multicall3Address = Multicall3.address(for: chain) else {
            return await fallbackPerCoin(coins)
        }

        do {
            let service = try EvmService.getService(forChain: chain)

            guard await isMulticallAvailable(chain: chain, multicall3Address: multicall3Address, service: service) else {
                return await fallbackPerCoin(coins)
            }

            let nativeCoins = coins.filter { $0.isNativeToken }
            let tokenCoins = coins.filter { !$0.isNativeToken }
            let contractAddresses = tokenCoins.map { $0.coinMeta.contractAddress }

            let result = try await service.fetchERC20Balances(
                contractAddresses: contractAddresses,
                walletAddress: address,
                multicall3Address: multicall3Address,
                includeNative: !nativeCoins.isEmpty
            )

            var updates: [CoinBalanceUpdate] = []
            updates.reserveCapacity(coins.count)

            for coin in nativeCoins {
                let value = result.native ?? 0
                updates.append(CoinBalanceUpdate(coinId: coin.coinId, rawBalance: String(value), stakedBalance: nil, bondedNodes: nil, error: nil))
            }
            for coin in tokenCoins {
                let value = result.balances[coin.coinMeta.contractAddress] ?? 0
                updates.append(CoinBalanceUpdate(coinId: coin.coinId, rawBalance: String(value), stakedBalance: nil, bondedNodes: nil, error: nil))
            }

            return updates
        } catch {
            logger.warning("Multicall3 batch failed for \(chain.name); falling back to per-coin: \(error.localizedDescription)")
            return await fallbackPerCoin(coins)
        }
    }

    /// Per-coin path used when a Multicall3 batch is unavailable or fails. Fans
    /// the individual fetches out concurrently so a batch failure reverts to the
    /// original parallel per-coin behaviour rather than serializing N RPCs.
    private func fallbackPerCoin(_ coins: [CoinIdentifier]) async -> [CoinBalanceUpdate] {
        return await withTaskGroup(of: CoinBalanceUpdate.self) { group in
            for coin in coins {
                group.addTask { [weak self] in
                    guard let self, !Task.isCancelled else {
                        return Self.emptyUpdate(for: coin)
                    }
                    return await self.fetchBalanceUpdate(for: coin)
                }
            }

            var updates: [CoinBalanceUpdate] = []
            updates.reserveCapacity(coins.count)
            for await update in group {
                updates.append(update)
            }
            return updates
        }
    }

    /// Hyperliquid (HyperEVM) is the newest chain in the Multicall3 allowlist, so
    /// its deployment is gated behind a one-time `eth_getCode` probe before the
    /// batch path is trusted; an absent contract maps to the per-coin fallback.
    /// Every other listed chain is verified against the canonical deployment list
    /// and trusted directly. The probe result is cached per process.
    private func isMulticallAvailable(chain: Chain, multicall3Address: String, service: EvmService) async -> Bool {
        guard chain == .hyperliquid else { return true }

        os_unfair_lock_lock(&multicallCodeLock)
        let cached = multicallCodeVerified[chain]
        os_unfair_lock_unlock(&multicallCodeLock)
        if let cached { return cached }

        do {
            let code = try await service.getCode(address: multicall3Address)
            let hasCode = !code.stripHexPrefix().isEmpty

            // Cache only definitive code / no-code results.
            os_unfair_lock_lock(&multicallCodeLock)
            multicallCodeVerified[chain] = hasCode
            os_unfair_lock_unlock(&multicallCodeLock)
            return hasCode
        } catch {
            // A transient probe failure stays uncached so the next refresh can
            // retry, rather than pinning the chain to the slow per-coin path for
            // the rest of the process.
            return false
        }
    }

    /// Fetch balance update for a single coin identifier
    private func fetchBalanceUpdate(for identifier: CoinIdentifier) async -> CoinBalanceUpdate {
        var rawBalance: String?
        var stakedBalance: String?
        var bondedNodes: [RuneBondNode]?
        var capturedError: Error?

        do {
            // Fetch raw balance
            rawBalance = try await fetchBalance(
                for: identifier.coinMeta,
                address: identifier.address
            )

            // Fetch staked balance if supported
            if let staked = try await fetchStakedBalance(for: identifier) {
                stakedBalance = staked
            }

            // Fetch bonded nodes if applicable
            bondedNodes = try await fetchBondedNodes(for: identifier)

        } catch {
            capturedError = error
            self.logger.warning("Fetch Balance error for \(identifier.ticker): \(error.localizedDescription)")
        }

        return CoinBalanceUpdate(
            coinId: identifier.coinId,
            rawBalance: rawBalance,
            stakedBalance: stakedBalance,
            bondedNodes: bondedNodes,
            error: capturedError
        )
    }

    /// Phase 3: Apply balance updates to coins in batch on MainActor
    @MainActor
    private func applyBalanceUpdates(_ updates: [CoinBalanceUpdate], to vault: Vault) throws {
        let coinsByID = Dictionary(vault.coins.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        // Apply all updates
        for update in updates where update.hasUpdates {
            guard let coin = coinsByID[update.coinId] else {
                logger.warning("Coin not found for update: \(update.coinId)")
                continue
            }

            // Update raw balance if present and changed
            if let rawBalance = update.rawBalance, coin.rawBalance != rawBalance {
                coin.rawBalance = rawBalance
            }

            // Update staked balance if present and changed
            if let stakedBalance = update.stakedBalance, coin.stakedBalance != stakedBalance {
                coin.stakedBalance = stakedBalance
            }

            // Update bonded nodes if present (transient property, always update)
            if let bondedNodes = update.bondedNodes {
                coin.bondedNodes = bondedNodes
            }
        }

        // Single save operation for all changes
        try Storage.shared.save()
    }

    @MainActor
    func updateBalance(for coin: Coin) async {
        // Fetch price
        do {
            try await cryptoPriceService.fetchPrice(coin: coin)
        } catch {
            if (error as? URLError)?.code != .cancelled {
                logger.warning("Fetch Price error: \(error.localizedDescription)")
            }
        }

        // Extract identifier (already on MainActor)
        let identifier = CoinIdentifier(from: coin)

        // Fetch update (async work happens off MainActor internally)
        let update = await fetchBalanceUpdate(for: identifier)

        // Apply update (already on MainActor)
        do {
            if let rawBalance = update.rawBalance, coin.rawBalance != rawBalance {
                coin.rawBalance = rawBalance
            }

            if let stakedBalance = update.stakedBalance, coin.stakedBalance != stakedBalance {
                coin.stakedBalance = stakedBalance
            }

            if let bondedNodes = update.bondedNodes {
                coin.bondedNodes = bondedNodes
            }

            try Storage.shared.save()
        } catch {
            if (error as? URLError)?.code != .cancelled {
                logger.warning("Update Balance error: \(error.localizedDescription)")
            }
        }
    }

    func fetchBalance(for coin: CoinMeta, address: String) async throws -> String {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            let blockChairData = try await utxo.fetchBlockchairData(coin: coin, address: address)
            return blockChairData.address?.balance?.description ?? "0"

        case .cardano:
            return try await cardano.getBalance(coin: coin, address: address)

        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            let service = ThorchainServiceFactory.getService(for: coin.chain)
            let thorBalances = try await service.fetchBalances(address)
            return thorBalances.balance(denom: coin.chain.ticker.lowercased(), coin: coin)

        case .solana:
            return try await sol.getSolanaBalance(coin: coin, address: address)

        case .sui:
            return try await sui.getBalance(coin: coin, address: address)

        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync, .ethereumSepolia, .mantle, .hyperliquid, .sei:
            let service = try EvmService.getService(forChain: coin.chain)
            return try await service.getBalance(coin: coin, address: address)

        case .gaiaChain, .dydx, .kujira, .osmosis, .terra, .terraClassic, .noble, .akash, .qbtc:
            let cosmosService = try CosmosService.getService(forChain: coin.chain)
            let balances = try await cosmosService.fetchBalances(coin: coin, address: address)

            // Determine the correct denom for each chain
            let denom: String
            switch coin.chain {
            case .terra, .terraClassic:
                denom = "uluna"
            default:
                denom = coin.chain.ticker.lowercased()
            }

            return balances.balance(denom: denom, coin: coin)

        case .mayaChain:
            let mayaBalance = try await maya.fetchBalances(address)
            return mayaBalance.balance(denom: coin.ticker.lowercased())

        case .polkadot:
            return try await dot.getBalance(address: address)

        case .bittensor:
            return try await tao.getBalance(address: address)

        case .ton:
            if coin.isNativeToken {
                return try await ton.getBalance(coin: coin, address: address)
            } else {
                return try await ton.getJettonBalance(coin: coin, address: address)
            }

        case .ripple:
            return try await ripple.getBalance(address: address)

        case .tron:
            return try await tron.getBalance(coin: coin, address: address)
        }
    }
}

private extension BalanceService {

    private var enableAutoCompoundStakedBalance: Bool { false }

    private func fetchBondedNodes(for identifier: CoinIdentifier) async throws -> [RuneBondNode]? {
        switch identifier.chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            guard identifier.ticker.caseInsensitiveCompare("RUNE") == .orderedSame else {
                return nil
            }

            let bondedNodes = try await thorchainAPIService.getBondedNodes(address: identifier.address)
            return bondedNodes.nodes

        case .mayaChain:
            guard identifier.isNativeToken, identifier.ticker.caseInsensitiveCompare("CACAO") == .orderedSame else {
                return nil
            }

            do {
                let bondedNodes = try await mayaChainAPIService.getBondedNodes(address: identifier.address)
                return bondedNodes.nodes.map { mayaNode in
                    RuneBondNode(
                        status: mayaNode.status,
                        address: mayaNode.address,
                        bond: mayaNode.bond
                    )
                }
            } catch {
                print("Error fetching MayaChain bonded nodes: \(error.localizedDescription)")
                return nil
            }

        default:
            return nil
        }
    }

    private func fetchStakedBalance(for identifier: CoinIdentifier) async throws -> String? {
        switch identifier.chain {
        case .thorChain:
            // Should be handled by `fetchBondedNodes`
            guard !identifier.isNativeToken else {
                return nil
            }

            switch identifier.ticker.uppercased() {
            case "TCY":
                let service = ThorchainServiceFactory.getService(for: identifier.chain)
                let tcyStakedBalance = await service.fetchTcyStakedAmount(address: identifier.address)

                if enableAutoCompoundStakedBalance {
                    // Auto-compound contributes to the displayed balance; on transient failure
                    // fall back to the staked-only amount rather than blanking the whole row.
                    let tcyAutoCompoundBalance = (try? await service.fetchTcyAutoCompoundAmount(address: identifier.address)) ?? .zero
                    let totalStakedBalance = tcyStakedBalance + tcyAutoCompoundBalance
                    return totalStakedBalance.description
                }

                let totalStakedBalance = tcyStakedBalance
                return totalStakedBalance.description
            case "RUJI":
                return (try? await ThorchainService.shared.fetchRujiStakeBalance(thorAddr: identifier.address))?.stakeAmount.description ?? "0"
            default:
                break
            }

            // Handle merge account balances for non-native tokens
            if !identifier.isNativeToken {
                let service = ThorchainServiceFactory.getService(for: identifier.chain)
                let mergedAccounts = await service.fetchMergeAccounts(address: identifier.address)

                if let matchedAccount = mergedAccounts.first(where: {
                    $0.pool.mergeAsset.metadata.symbol.caseInsensitiveCompare(identifier.ticker) == .orderedSame
                }) {
                    let amountInDecimal = matchedAccount.size.amount.toDecimal()
                    return amountInDecimal.description
                }
            }

            // Fallback return value
            return "0"

        case .mayaChain:
            // Only CACAO (native token) supports staking via CACAO pool
            guard identifier.isNativeToken, identifier.ticker.uppercased() == "CACAO" else {
                return nil
            }

            do {
                // Fetch CACAO pool position
                let position = try await mayaChainAPIService.getCacaoPoolPosition(address: identifier.address)

                // Return staked amount (current value in CACAO)
                let stakedAmountInAtomicUnits = position.stakedAmount
                let stakedAmountBigInt = stakedAmountInAtomicUnits.description.toBigInt()
                return stakedAmountBigInt.description
            } catch {
                print("Error fetching MayaChain CACAO staking balance: \(error.localizedDescription)")
                return "0"
            }

        case .terra, .terraClassic, .qbtc:
            // LUNA / LUNC / QBTC delegations are the DeFi position. Sum the
            // per-validator balances (all returned in the chain's staking denom,
            // base units) so `DefiBalanceService` can roll them into the
            // vault-wide DeFi total without re-fetching. Only native tokens stake.
            guard identifier.isNativeToken else { return nil }
            do {
                let delegations = try await CosmosStakingService().fetchDelegations(
                    chain: identifier.chain,
                    address: identifier.address
                )
                let total = delegations
                    .compactMap { Decimal(string: $0.balance.amount) }
                    .reduce(Decimal.zero, +)
                return total.description
            } catch {
                logger.warning("Failed to fetch Cosmos delegations for \(identifier.address, privacy: .private): \(error.localizedDescription, privacy: .public)")
                return nil
            }

        case .tron:
            // Native TRX is the only stake-able asset on Tron. Frozen (Stake 2.0
            // bandwidth + energy) plus unfreezing (in cooldown) TRX represent
            // the user's DeFi position. Returning `nil` on transient failure
            // preserves the previously persisted value rather than clobbering
            // it with 0.
            guard identifier.isNativeToken else { return nil }
            do {
                let account = try await TronService.shared.getAccount(address: identifier.address)
                let totalSun = account.frozenBandwidthSun + account.frozenEnergySun + account.unfreezingTotalSun
                return Decimal(totalSun).description
            } catch {
                logger.warning("Failed to fetch Tron frozen balance for \(identifier.address, privacy: .private): \(error.localizedDescription, privacy: .public)")
                return nil
            }

        default:
            // All other chains currently don't support staking
            return nil
        }
    }

    /// Auto-discover Cardano native tokens (CNT) held at the vault's Cardano
    /// address and add any new ones. Mirrors vultisig-windows' `CoinFinder`
    /// silent-discovery behaviour. Run after each balance refresh.
    @MainActor
    private func discoverCardanoNativeTokens(vault: Vault) async {
        guard let cardanoNative = vault.coins.first(where: { $0.chain == .cardano && $0.isNativeToken }) else {
            return
        }

        let address = cardanoNative.address
        let knownContractAddresses = Set(
            vault.coins
                .filter { $0.chain == .cardano && !$0.isNativeToken }
                .map { $0.contractAddress.lowercased() }
        )

        let discovered: [CardanoTokenMetadata]
        do {
            discovered = try await CardanoNativeTokensService.shared.discoverTokens(address: address)
        } catch {
            if (error as? URLError)?.code != .cancelled {
                logger.warning("Cardano CNT discovery failed: \(error.localizedDescription)")
            }
            return
        }

        let newTokens = discovered.filter { !knownContractAddresses.contains($0.assetId) }
        guard !newTokens.isEmpty else { return }

        // Prefer the built-in registry entry when we know the asset — it carries
        // a human ticker (`USDM` rather than the `_USDM` derived from masking
        // the CIP-67 prefix), the bundled logo asset, and a working
        // `priceProviderId`. Falls back to the API-derived metadata for assets
        // the registry doesn't know about.
        let newCoinMetas = newTokens.map { metadata in
            if let known = TokensStore.findTokenMeta(chain: .cardano, contractAddress: metadata.assetId) {
                return known
            }
            return CoinMeta(
                chain: .cardano,
                ticker: metadata.ticker,
                logo: metadata.registryLogo ?? .empty,
                decimals: metadata.decimals,
                priceProviderId: .empty,
                contractAddress: metadata.assetId,
                isNativeToken: false
            )
        }

        do {
            try await CoinService.addToChain(assets: newCoinMetas, to: vault)
        } catch {
            logger.warning("Cardano CNT auto-add failed: \(error.localizedDescription)")
        }
    }
}
