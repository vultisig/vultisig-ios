//
//  KeyImportChainsSetupViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import Foundation
import WalletCore

enum KeyImportChainsState {
    case scanningChains
    case activeChains
    case customizeChains
}

struct CoinMetaBalance {
    let coin: CoinMeta
    let balance: Decimal
}

final class KeyImportChainsSetupViewModel: ObservableObject {
    @Published var state: KeyImportChainsState = .scanningChains
    @Published var selectedChains = [Chain]()
    @Published var activeChains = [KeyImportChain]()
    @Published var otherChains = [KeyImportChain]()

    var selectedChainsCount: Int { selectedChains.count }
    var maxChainsExceeded: Bool { selectedChainsCount > maxChains }
    var buttonDisabled: Bool { selectedChains.isEmpty || maxChainsExceeded }
    var buttonTitle: String {
        maxChainsExceeded ? String(format: "youCanSelectXChains".localized, maxChains) : "continue".localized
    }
    var chainsToImport: [Chain] {
        selectedChains.isEmpty ? activeChains.map(\.chain) : selectedChains
    }

    let maxChains: Int = 4

    private let balanceService = BalanceService.shared
    private let priceService = CryptoPriceService.shared

    init() {}
    
    func onLoad(mnemonic: String) async {
        let activeChains = await fetchActiveChains(mnemonic: mnemonic)
        await MainActor.run {
            self.activeChains = activeChains
            self.otherChains = Chain.allCases
                .filter { !activeChains.map(\.chain).contains($0) }
                .map { KeyImportChain(chain: $0, balance: Decimal.zero.formatToFiat()) }
            self.state = activeChains.isEmpty ? .customizeChains : .activeChains
        }
    }
    
    func fetchActiveChains(mnemonic: String) async -> [KeyImportChain] {
        // 1. Create HDWallet from mnemonic
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            print("Failed to create HDWallet from mnemonic")
            return []
        }

        // 2. Group TokensStore.TokenSelectionAssets by chain
        let groupedByChain = Dictionary(grouping: TokensStore.TokenSelectionAssets) { $0.chain }

        // 3. For each chain, calculate total balance in fiat
        var chainTokens: [(chain: Chain, tokens: [CoinMetaBalance])] = []

        for (chain, tokens) in groupedByChain {
            // Generate address for the chain
            guard let address = generateAddress(for: chain, wallet: wallet) else {
                continue
            }
            
            // 4. For each token on the chain, fetch balance
            var tokenBalances: [CoinMetaBalance] = []
            for token in tokens {
                do {
                    let balanceString = try await balanceService.fetchBalance(for: token, address: address)
                    guard let balance = Decimal(string: balanceString), balance > 0 else {
                        continue
                    }

                    tokenBalances.append(CoinMetaBalance(coin: token, balance: balance))
                } catch {
                    // Skip tokens that fail to fetch
                    continue
                }
            }
            
            if !tokenBalances.isEmpty {
                chainTokens.append((chain, tokenBalances))
            }
        }
        
        let pricesToFetch = chainTokens
            .map(\.tokens)
            .flatMap { $0 }
            .map(\.coin)
        try? await priceService.fetchPrices(coins: pricesToFetch)

        // 5. Get fiat for each token balance
        var chainBalances: [(chain: Chain, fiatBalance: Decimal)] = []
        for chainBalance in chainTokens {
            let totalChainBalance = chainBalance.tokens.compactMap { token -> Decimal? in
                guard let rate = RateProvider.shared.rate(for: token.coin) else {
                    return nil
                }
                
                return token.balance / pow(10, token.coin.decimals) * Decimal(rate.value)
            }.reduce(.zero, +)
            
            if totalChainBalance > 0 {
                chainBalances.append((chainBalance.chain, totalChainBalance))
            }
        }
        
        // 6. Sort by fiat amount (descending)
        chainBalances.sort { $0.fiatBalance > $1.fiatBalance }

        // 7. Return first 4 chains
        let topChains = Array(chainBalances.prefix(maxChains))
        return topChains.map { item in
            KeyImportChain(
                chain: item.chain,
                balance: item.fiatBalance.formatToFiat()
            )
        }
    }

    private func generateAddress(for chain: Chain, wallet: HDWallet) -> String? {
        let privateKey = wallet.getKeyForCoin(coin: chain.coinType)
        let pubKey = privateKey.getPublicKey(coinType: chain.coinType).data.hexString
        return try? CoinFactory.generateAddress(
            chain: chain,
            publicKeyECDSA: pubKey,
            publicKeyEdDSA: pubKey,
            hexChainCode: wallet.rootChainCodeHex(),
            isDerived: true
        )
    }
    
    func isSelected(chain: KeyImportChain) -> Bool {
        selectedChains.contains(chain.chain)
    }
    
    func toggleSelection(chain: KeyImportChain, isSelected: Bool) {
        if isSelected {
            selectedChains.append(chain.chain)
        } else {
            selectedChains.removeAll { $0 == chain.chain }
        }
    }
}
