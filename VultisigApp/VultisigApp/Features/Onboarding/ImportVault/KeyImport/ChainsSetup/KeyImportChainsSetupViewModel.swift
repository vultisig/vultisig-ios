//
//  KeyImportChainsSetupViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import Foundation
import OSLog
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

struct ChainBalanceResult {
    let chain: Chain
    let tokens: [CoinMetaBalance]
    let derivationPath: DerivationPath?
}

/// Maps a derivation path to its derivationPath identifier
struct DerivationOption {
    let derivation: Derivation
    let derivationPath: DerivationPath
}

/// Result of fetching balances for a specific derivation
struct DerivationBalanceResult {
    let tokens: [CoinMetaBalance]
    let fiatBalance: Decimal
    let derivationPath: DerivationPath?
}

final class KeyImportChainsSetupViewModel: ObservableObject {
    @Published var state: KeyImportChainsState = .scanningChains
    @Published var selectedChains = [Chain]()
    @Published var activeChains = [KeyImportChain]()
    @Published var otherChains = [KeyImportChain]()
    @Published var selectedDerivationPath: DerivationPath = .default

    private var chainBalanceResults = [ChainBalanceResult]()
    private let logger = Logger(subsystem: "com.vultisig.VultisigApp", category: "KeyImport")

    /// Chains that have alternative derivation paths to check during import.
    /// The array order determines priority when balances are equal (first match wins).
    /// Add new chains/derivations here to support additional derivation types in the future.
    private let alternativeDerivations: [Chain: [DerivationOption]] = [
        .solana: [
            DerivationOption(derivation: .solanaSolana, derivationPath: .phantom)
            // Add more Solana derivations here in the future, e.g.:
            // DerivationOption(derivation: .someLedgerDerivation, derivationPath: .ledger)
        ]
    ]

    var selectedChainsCount: Int { selectedChains.count }
    var buttonDisabled: Bool { selectedChains.isEmpty }
    var chainsToImport: [Chain] {
        selectedChains.isEmpty ? activeChains.map(\.chain) : selectedChains
    }

    func derivationPath(for chain: Chain) -> DerivationPath {
        // Get all results for this chain
        let chainResults = chainBalanceResults.filter { $0.chain == chain }

        // If user has manually selected a path, use it
        if chainResults.contains(where: { $0.derivationPath == selectedDerivationPath }) {
            return selectedDerivationPath
        }

        // Otherwise, return the first result (which should be the one with highest balance)
        return chainResults.first?.derivationPath ?? .default
    }

    var solanaderivationPath: DerivationPath {
        derivationPath(for: .solana)
    }

    /// Checks if a chain has multiple derivation options with balances
    func hasMultipleDerivations(for chain: Chain) -> Bool {
        guard let _ = alternativeDerivations[chain] else {
            return false
        }
        // Check if we found multiple balance results for this chain during scanning
        return chainBalanceResults.filter { $0.chain == chain }.count > 1
    }

    /// Updates the derivation path for a specific chain
    func selectDerivationPath(_ path: DerivationPath, for chain: Chain) {
        // Find the chain balance result and update it
        if let index = chainBalanceResults.firstIndex(where: { $0.chain == chain && $0.derivationPath == path }) {
            // Move this result to be the primary one by ensuring it's first
            let result = chainBalanceResults[index]
            chainBalanceResults.remove(at: index)
            chainBalanceResults.insert(result, at: 0)
        }
        selectedDerivationPath = path
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
        logger.info("🚀 Starting active chains discovery...")

        guard let wallet = createWallet(from: mnemonic) else {
            logger.error("❌ Failed to create wallet from mnemonic")
            return []
        }

        let groupedByChain = groupTokensByChain()
        logger.info("📋 Scanning \(groupedByChain.count) chains for balances")

        let results = await fetchBalancesForChains(groupedByChain: groupedByChain, wallet: wallet)
        guard !Task.isCancelled else {
            logger.warning("⚠️ Fetch cancelled")
            return []
        }

        // Store results to access derivation types later
        await MainActor.run {
            self.chainBalanceResults = results
        }

        logger.info("💵 Fetching current prices for tokens...")
        await fetchPricesForTokens(results: results)

        let chainBalances = calculateChainFiatBalances(results: results)
        let sortedChains = sortChainsByBalance(chainBalances: chainBalances)

        let activeChains = topChainsAsKeyImportChains(sortedChains: sortedChains)
        logger.info("✨ Discovery complete! Found \(activeChains.count) active chain(s)")

        return activeChains
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
            logger.error("Failed to create HDWallet from mnemonic")
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
    ) async -> [ChainBalanceResult] {
        var results = [ChainBalanceResult]()
        let totalChains = groupedByChain.count
        var processedChains = 0

        logger.info("📊 Starting balance fetch for \(totalChains) chains")

        for (chain, tokens) in groupedByChain {
            guard !Task.isCancelled else {
                logger.warning("⚠️ Balance fetch cancelled after \(processedChains)/\(totalChains) chains")
                return []
            }

            let chainResults = await fetchBalancesForChain(chain: chain, tokens: tokens, wallet: wallet)
            results.append(contentsOf: chainResults)

            processedChains += 1
            logger.debug("✅ Completed \(processedChains)/\(totalChains) chains")
        }

        logger.info("🎉 Finished balance fetch for all chains. Found balances on \(results.count) derivation paths")
        return results
    }

    func fetchBalancesForChain(
        chain: Chain,
        tokens: [CoinMeta],
        wallet: HDWallet
    ) async -> [ChainBalanceResult] {
        let startTime = Date()
        let alternativeCount = alternativeDerivations[chain]?.count ?? 0
        let totalDerivations = 1 + alternativeCount // default + alternatives

        logger.debug("🔍 [\(chain.ticker)] Starting balance check for \(totalDerivations) derivation path(s)")

        var derivationResults = [DerivationBalanceResult]()

        // Check default derivation
        let defaultAddress = wallet.getAddressForCoin(coin: chain.coinType).description
        logger.debug("   📍 [\(chain.ticker)] Checking default derivation: \(defaultAddress)")
        let defaultResult = await fetchBalancesForDerivation(
            address: defaultAddress,
            tokens: tokens,
            derivationPath: nil
        )
        derivationResults.append(defaultResult)
        logger.debug("   💰 [\(chain.ticker)] Default balance: $\(defaultResult.fiatBalance)")

        // Check all alternative derivations for this chain
        if let alternatives = alternativeDerivations[chain] {
            for option in alternatives {
                let address = wallet.getAddressDerivation(coin: chain.coinType, derivation: option.derivation)
                logger.debug("   📍 [\(chain.ticker)] Checking \(option.derivationPath.rawValue) derivation: \(address)")
                let result = await fetchBalancesForDerivation(
                    address: address,
                    tokens: tokens,
                    derivationPath: option.derivationPath
                )
                derivationResults.append(result)
                logger.debug("   💰 [\(chain.ticker)] \(option.derivationPath.rawValue) balance: $\(result.fiatBalance)")
            }
        }

        // Filter results to only those with balances
        let resultsWithBalance = derivationResults.filter { $0.fiatBalance > 0 }

        let elapsed = Date().timeIntervalSince(startTime)

        // If no derivations have balance, return empty array
        guard !resultsWithBalance.isEmpty else {
            logger.debug("❌ [\(chain.ticker)] No balance found on any derivation path (took \(String(format: "%.2f", elapsed))s)")
            return []
        }

        logger.info("✅ [\(chain.ticker)] Found balance on \(resultsWithBalance.count)/\(totalDerivations) derivation path(s) (took \(String(format: "%.2f", elapsed))s)")

        // Convert all derivation results with balances to ChainBalanceResults
        return resultsWithBalance.map { result in
            ChainBalanceResult(
                chain: chain,
                tokens: result.tokens,
                derivationPath: result.derivationPath
            )
        }
    }

    func fetchBalancesForDerivation(
        address: String,
        tokens: [CoinMeta],
        derivationPath: DerivationPath?
    ) async -> DerivationBalanceResult {
        let mergedTokens = await mergeWithDiscoveredTokens(tokens: tokens, address: address)
        let balances = await fetchBalancesForTokens(tokens: mergedTokens, address: address)
        let totalFiat = calculateTotalFiatBalance(for: balances)
        return DerivationBalanceResult(tokens: balances, fiatBalance: totalFiat, derivationPath: derivationPath)
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
            logger.warning("Failed to fetch discovered tokens for \(nativeToken.chain.name): \(error.localizedDescription)")
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

    func fetchPricesForTokens(results: [ChainBalanceResult]) async {
        let coinsToFetchPrices = results
            .flatMap { $0.tokens }
            .map { $0.coin }

        try? await priceService.fetchPrices(coins: coinsToFetchPrices)
    }

    func calculateChainFiatBalances(
        results: [ChainBalanceResult]
    ) -> [(chain: Chain, fiatBalance: Decimal)] {
        // Group results by chain
        let groupedByChain = Dictionary(grouping: results) { $0.chain }

        var chainBalances: [(chain: Chain, fiatBalance: Decimal)] = []

        for (chain, chainResults) in groupedByChain {
            // For each chain, calculate balances for all derivations and take the max
            let balances = chainResults.map { result in
                calculateTotalFiatBalance(for: result.tokens)
            }

            if let maxBalance = balances.max(), maxBalance > 0 {
                chainBalances.append((chain, maxBalance))
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
