//
//  BalanceService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.04.2024.
//

import Foundation
import OSLog
import SwiftData

class BalanceService {

    static let shared = BalanceService()
    private let logger = Logger(subsystem: "com.vultisig.app", category: "balance-service")

    private let utxo = BlockchairService.shared
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let maya = MayachainService.shared
    private let dot = PolkadotService.shared
    private let ton = TonService.shared
    private let ripple = RippleService.shared
    private let tron = TronService.shared
    private let cardano = CardanoService.shared

    private let thorchainAPIService = THORChainAPIService()
    private let mayaChainAPIService = MayaChainAPIService()

    private let cryptoPriceService = CryptoPriceService.shared

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
        // Phase 0: Fetch prices (already async-safe)
        do {
            try await cryptoPriceService.fetchPrices(vault: vault)
        } catch {
            if (error as? URLError)?.code != .cancelled {
                logger.warning("Fetch Rates error: \(error.localizedDescription)")
            }
        }

        // Phase 1: Extract coin identifiers on MainActor
        let coinIdentifiers = await extractCoinIdentifiers(from: vault)

        // Phase 2: Fetch balances concurrently (off MainActor)
        let updates = await fetchBalanceUpdates(for: coinIdentifiers)

        // Phase 3: Apply updates in batch on MainActor
        do {
            try await applyBalanceUpdates(updates, to: vault)
        } catch {
            logger.error("Update Balances error: \(error.localizedDescription)")
        }
    }

    /// Phase 1: Extract coin identifiers on MainActor
    @MainActor
    private func extractCoinIdentifiers(from vault: Vault) -> [CoinIdentifier] {
        return vault.coins.map { CoinIdentifier(from: $0) }
    }

    /// Phase 2: Fetch balance updates concurrently using identifiers
    private func fetchBalanceUpdates(for identifiers: [CoinIdentifier]) async -> [CoinBalanceUpdate] {
        await withTaskGroup(of: CoinBalanceUpdate.self) { group in
            var updates: [CoinBalanceUpdate] = []
            updates.reserveCapacity(identifiers.count)

            for identifier in identifiers {
                group.addTask { [weak self] in
                    guard let self, !Task.isCancelled else {
                        return CoinBalanceUpdate(
                            coinId: identifier.coinId,
                            rawBalance: nil,
                            stakedBalance: nil,
                            bondedNodes: nil,
                            error: nil
                        )
                    }

                    return await self.fetchBalanceUpdate(for: identifier)
                }
            }

            for await update in group {
                updates.append(update)
            }

            return updates
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
        // Create lookup dictionary for O(1) access (follows DefiPositionsStorageService pattern)
        let coinsByID = Dictionary(uniqueKeysWithValues: vault.coins.map { ($0.id, $0) })

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
            return try await cardano.getBalance(address: address)

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

        case .gaiaChain, .dydx, .kujira, .osmosis, .terra, .terraClassic, .noble, .akash:
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
                    let tcyAutoCompoundBalance = await service.fetchTcyAutoCompoundAmount(address: identifier.address)
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

        default:
            // All other chains currently don't support staking
            return nil
        }
    }

}
