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
    case noActiveChains
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
    var buttonDisabled: Bool { selectedChains.isEmpty }
    var chainsToImport: [Chain] {
        selectedChains.isEmpty ? activeChains.map(\.chain) : selectedChains
    }
    
    var screenTitle: String {
        switch state {
        case .scanningChains:
            "importSeedphrase".localized
        case .customizeChains:
            "selectChains".localized
        case .activeChains, .noActiveChains:
            ""
        }
    }

    private let balanceService = BalanceService.shared
    private let priceService = CryptoPriceService.shared
    
    var fetchChainsTask: Task<Void, Never>?

    init() {}
    
    func onLoad(mnemonic: String) async {
        fetchChainsTask = Task {
            let activeChains = await fetchActiveChains(mnemonic: mnemonic)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                updateState(with: activeChains, skipped: false)
            }
        }
    }
    
    func updateState(with activeChains: [KeyImportChain], skipped: Bool) {
        self.activeChains = activeChains
        let filteredChains = activeChains.isEmpty ? Chain.enabledChains : Chain.enabledChains
            .filter { !activeChains.map(\.chain).contains($0) }
        self.otherChains = filteredChains
            .map { KeyImportChain(chain: $0, balance: Decimal.zero.formatToFiat()) }
        
        let newState: KeyImportChainsState
        if activeChains.isEmpty {
            newState = skipped ? .customizeChains : .noActiveChains
        } else {
            newState = .activeChains
        }
        
        self.state = newState
    }
    
    func fetchActiveChains(mnemonic: String) async -> [KeyImportChain] {
        guard let wallet = createWallet(from: mnemonic) else {
            return []
        }

        let groupedByChain = groupTokensByChain()
        let chainTokens = await fetchBalancesForChains(groupedByChain: groupedByChain, wallet: wallet)
        guard !Task.isCancelled else { return [] }

        await fetchPricesForTokens(chainTokens: chainTokens)

        let chainBalances = calculateChainFiatBalances(chainTokens: chainTokens)
        let sortedChains = sortChainsByBalance(chainBalances: chainBalances)

        return topChainsAsKeyImportChains(sortedChains: sortedChains)
    }

    func isSelected(chain: Chain) -> Bool {
        selectedChains.contains(chain)
    }

    func toggleSelection(chain: Chain, isSelected: Bool) {
        if isSelected {
            selectedChains.append(chain)
        } else {
            selectedChains.removeAll { $0 == chain }
        }
    }
    
    func onSelectChainsManually() {
        fetchChainsTask?.cancel()
        fetchChainsTask = nil
        updateState(with: [], skipped: true)
    }
}

// MARK: - Private Helpers

private extension KeyImportChainsSetupViewModel {
    func createWallet(from mnemonic: String) -> HDWallet? {
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            print("Failed to create HDWallet from mnemonic")
            return nil
        }
        return wallet
    }

    func groupTokensByChain() -> [Chain: [CoinMeta]] {
        Dictionary(grouping: TokensStore.TokenSelectionAssets) { $0.chain }
    }

    func fetchBalancesForChains(
        groupedByChain: [Chain: [CoinMeta]],
        wallet: HDWallet
    ) async -> [(chain: Chain, tokens: [CoinMetaBalance])] {
        var chainTokens: [(chain: Chain, tokens: [CoinMetaBalance])] = []

        for (chain, tokens) in groupedByChain {
            guard !Task.isCancelled else { return [] }
            
            let address = wallet.getAddressForCoin(coin: chain.coinType).description
            
            // Merge discovered tokens with static tokens
            let allTokens = await mergeWithDiscoveredTokens(tokens: tokens, address: address)

            let tokenBalances = await fetchBalancesForTokens(tokens: allTokens, address: address)

            if !tokenBalances.isEmpty {
                chainTokens.append((chain, tokenBalances))
            }
        }

        return chainTokens
    }

    func mergeWithDiscoveredTokens(tokens: [CoinMeta], address: String) async -> [CoinMeta] {
        // Find the native token for this chain
        guard let nativeToken = tokens.first(where: { $0.isNativeToken }) else {
            return tokens
        }

        // Fetch discovered tokens for this chain
        do {
            let discoveredTokens = try await CoinService.fetchDiscoveredTokens(
                nativeCoin: nativeToken,
                address: address
            )

            // Merge and deduplicate tokens
            let allTokens = tokens + discoveredTokens
            let uniqueTokens = allTokens.uniqueBy { token in
                // Create unique key: chain + ticker + contractAddress
                "\(token.chain.rawValue)_\(token.ticker)_\(token.contractAddress)"
            }

            return uniqueTokens
        } catch {
            // If fetching discovered tokens fails, return original tokens
            print("Failed to fetch discovered tokens for \(nativeToken.chain): \(error.localizedDescription)")
            return tokens
        }
    }

    func fetchBalancesForTokens(
        tokens: [CoinMeta],
        address: String
    ) async -> [CoinMetaBalance] {
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

        return tokenBalances
    }

    func fetchPricesForTokens(chainTokens: [(chain: Chain, tokens: [CoinMetaBalance])]) async {
        let coinsToFetchPrices = chainTokens
            .flatMap { $0.tokens }
            .map { $0.coin }

        try? await priceService.fetchPrices(coins: coinsToFetchPrices)
    }

    func calculateChainFiatBalances(
        chainTokens: [(chain: Chain, tokens: [CoinMetaBalance])]
    ) -> [(chain: Chain, fiatBalance: Decimal)] {
        var chainBalances: [(chain: Chain, fiatBalance: Decimal)] = []

        for chainBalance in chainTokens {
            let totalFiatBalance = calculateTotalFiatBalance(for: chainBalance.tokens)

            if totalFiatBalance > 0 {
                chainBalances.append((chainBalance.chain, totalFiatBalance))
            }
        }

        return chainBalances
    }

    func calculateTotalFiatBalance(for tokens: [CoinMetaBalance]) -> Decimal {
        tokens.compactMap { token -> Decimal? in
            guard let rate = RateProvider.shared.rate(for: token.coin) else {
                return nil
            }

            let tokenBalance = token.balance / pow(10, token.coin.decimals)
            return tokenBalance * Decimal(rate.value)
        }.reduce(.zero, +)
    }

    func sortChainsByBalance(
        chainBalances: [(chain: Chain, fiatBalance: Decimal)]
    ) -> [(chain: Chain, fiatBalance: Decimal)] {
        chainBalances.sorted { $0.fiatBalance > $1.fiatBalance }
    }

    func topChainsAsKeyImportChains(
        sortedChains: [(chain: Chain, fiatBalance: Decimal)]
    ) -> [KeyImportChain] {
        sortedChains.map { item in
            KeyImportChain(
                chain: item.chain,
                balance: item.fiatBalance.formatToFiat()
            )
        }
    }

    func generateAddress(for chain: Chain, wallet: HDWallet) -> String? {
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
}
