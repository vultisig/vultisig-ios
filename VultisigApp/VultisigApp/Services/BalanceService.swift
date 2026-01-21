//
//  BalanceService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.04.2024.
//

import Foundation
import SwiftData

class BalanceService {

    static let shared = BalanceService()

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

    func updateBalances(vault: Vault) async {
        do {
            try await cryptoPriceService.fetchPrices(vault: vault)
        } catch {
            print("error \(error)")
            print("Fetch Rates error: \(error.localizedDescription)")
        }

        do {
            await withTaskGroup(of: Void.self) { group in
                for coin in vault.coins {
                    group.addTask { [unowned self]  in
                        if !Task.isCancelled {
                            do {
                                let rawBalance = try await fetchBalance(for: coin)
                                try await updateCoin(coin, rawBalance: rawBalance)

                                if let stakedBalance = try await fetchStakedBalance(for: coin) {
                                    try await updateCoin(coin, stakedBalance: stakedBalance)
                                }

                                try await updateBondedIfNeeded(for: coin)
                            } catch {
                                print("Fetch Balances error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }

            try await Storage.shared.save()
        } catch {
            print("Update Balances error: \(error.localizedDescription)")
        }
    }

    func updateBalance(for coin: Coin) async {
        print("Updating balance for coin: \(coin.ticker) on chain: \(coin.chain.rawValue)")
        do {
            try await cryptoPriceService.fetchPrice(coin: coin)
        } catch {
            print("Fetch Price error: \(error.localizedDescription)")
        }
        do {
            let rawBalance = try await fetchBalance(for: coin)
            try await updateCoin(coin, rawBalance: rawBalance)

            if let stakedBalance = try await fetchStakedBalance(for: coin) {
                try await updateCoin(coin, stakedBalance: stakedBalance)
            }
            try await updateBondedIfNeeded(for: coin)
            try await MainActor.run {
                try Storage.shared.save()
            }
        } catch {
            print("Fetch Balance error: \(error.localizedDescription)")
        }
    }

    func fetchBalance(for coin: CoinMeta, address: String) async throws -> String {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            let blockChairData = try await utxo.fetchBlockchairData(coin: coin, address: address)
            return blockChairData.address?.balance?.description ?? "0"

        case .cardano:
            return try await cardano.getBalance(coin: coin, address: address)

        case .thorChain, .thorChainStagenet:
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
            return try await ripple.getBalance(coin: coin, address: address)

        case .tron:
            return try await tron.getBalance(coin: coin, address: address)
        }
    }
}

private extension BalanceService {

    private var enableAutoCompoundStakedBalance: Bool { false }

    func fetchStakedBalance(for coin: Coin) async throws -> String? {
        switch coin.chain {
        case .thorChain:
            // Should be handled by `updateBondedIfNeeded`
            guard !coin.isNativeToken else {
                return nil
            }

            switch coin.ticker.uppercased() {
            case "TCY":
                let service = ThorchainServiceFactory.getService(for: coin.chain)
                let tcyStakedBalance = await service.fetchTcyStakedAmount(address: coin.address)

                if enableAutoCompoundStakedBalance {
                    let tcyAutoCompoundBalance = await service.fetchTcyAutoCompoundAmount(address: coin.address)
                    let totalStakedBalance = tcyStakedBalance + tcyAutoCompoundBalance
                    return totalStakedBalance.description
                }

                let totalStakedBalance = tcyStakedBalance
                return totalStakedBalance.description
            case "RUJI":
                return (try? await ThorchainService.shared.fetchRujiStakeBalance(thorAddr: coin.address, tokenSymbol: "RUJI"))?.stakeAmount.description ?? "0"
            default:
                break
            }

            // Handle merge account balances for non-native tokens
            if !coin.isNativeToken {
                let service = ThorchainServiceFactory.getService(for: coin.chain)
                let mergedAccounts = await service.fetchMergeAccounts(address: coin.address)

                if let matchedAccount = mergedAccounts.first(where: {
                    $0.pool.mergeAsset.metadata.symbol.caseInsensitiveCompare(coin.ticker) == .orderedSame
                }) {
                    let amountInDecimal = matchedAccount.size.amount.toDecimal()
                    return amountInDecimal.description
                }
            }

            // Fallback return value
            return "0"

        case .mayaChain:
            // Only CACAO (native token) supports staking via CACAO pool
            guard coin.isNativeToken, coin.ticker.uppercased() == "CACAO" else {
                return nil
            }

            do {
                // Fetch CACAO pool position
                let position = try await mayaChainAPIService.getCacaoPoolPosition(address: coin.address)

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

    func fetchBalance(for coin: Coin) async throws -> String {
        try await fetchBalance(for: coin.toCoinMeta(), address: coin.address)
    }

    @MainActor func updateCoin(_ coin: Coin, rawBalance: String) async throws {
        guard coin.rawBalance != rawBalance else {
            return
        }

        coin.rawBalance = rawBalance
    }

    @MainActor func updateCoin(_ coin: Coin, stakedBalance: String) async throws {
        guard coin.stakedBalance != stakedBalance else {
            return
        }

        coin.stakedBalance = stakedBalance
    }
}

private extension BalanceService {
    func updateBondedIfNeeded(for coin: Coin) async throws {
        switch coin.chain {
        case .thorChain, .thorChainStagenet:
            // Handle RUNE bonds
            guard coin.ticker.caseInsensitiveCompare("RUNE") == .orderedSame else {
                return
            }

            let bondedNodes = try await thorchainAPIService.getBondedNodes(address: coin.address)
            await MainActor.run {
                coin.bondedNodes = bondedNodes.nodes
            }
            try await updateCoin(coin, stakedBalance: bondedNodes.totalBonded.description)

        case .mayaChain:
            // Handle CACAO bonds - Maya uses LP units bonded to nodes
            guard coin.isNativeToken, coin.ticker.caseInsensitiveCompare("CACAO") == .orderedSame else {
                return
            }

            do {
                let bondedNodes = try await mayaChainAPIService.getBondedNodes(address: coin.address)

                // Convert Maya bonds to the same format as THORChain for consistency
                let nodes = bondedNodes.nodes.map { mayaNode in
                    RuneBondNode(
                        status: mayaNode.status,
                        address: mayaNode.address,
                        bond: mayaNode.bond
                    )
                }

                await MainActor.run {
                    coin.bondedNodes = nodes
                }

                // Note: For Maya, staked balance already includes CACAO pool staking
                // Bond value is in LP units which represent CACAO value, but we don't
                // add it to stakedBalance to avoid double counting with CACAO pool staking
            } catch {
                print("Error fetching MayaChain bonded nodes: \(error.localizedDescription)")
            }

        default:
            // Other chains don't support bonding
            return
        }
    }
}
