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

struct ChainBalanceResult {
    let chain: Chain
    let nativeCoin: CoinMeta
    let derivationPath: DerivationPath?
}

/// Maps a derivation path to its derivationPath identifier
struct DerivationOption {
    let derivation: Derivation
    let derivationPath: DerivationPath
}

/// Result of fetching balances for a specific derivation
struct DerivationBalanceResult {
    let nativeCoin: CoinMeta
    let hasBalance: Bool
    let derivationPath: DerivationPath?
}

final class KeyImportChainsSetupViewModel: ObservableObject {
    @Published var state: KeyImportChainsState = .scanningChains
    @Published var selectedChains = [Chain]()
    @Published var activeChains = [KeyImportChain]()
    @Published var otherChains = [KeyImportChain]()
    @Published var selectedDerivationPath: DerivationPath = .default
    @Published var isLoading: Bool = false

    private var chainBalanceResults = [ChainBalanceResult]()
    private let logger = Logger(subsystem: "com.vultisig.VultisigApp", category: "KeyImport")
    private var wallet: HDWallet?

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

    /// Checks if a chain has alternative derivation paths defined
    func hasAlternativeDerivations(for chain: Chain) -> Bool {
        return alternativeDerivations[chain] != nil
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

    var fetchChainsTask: Task<Void, Never>?

    init() {}

    func onLoad(mnemonic: String) {
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
        let filteredChains = activeChains.isEmpty ? Chain.keyImportEnabledChains : Chain.keyImportEnabledChains
            .filter { !activeChains.map(\.chain).contains($0) }
        self.otherChains = filteredChains
            .map { KeyImportChain(chain: $0) }

        let newState: KeyImportChainsState
        if activeChains.isEmpty {
            newState = skipped ? .customizeChains : .noActiveChains
        } else {
            newState = .activeChains
        }

        self.state = newState
    }

    func fetchActiveChains(mnemonic: String) async -> [KeyImportChain] {
        let startTime = Date()
        logger.info("🚀 Starting active chains discovery...")

        guard let wallet = createWallet(from: mnemonic) else {
            logger.error("❌ Failed to create wallet from mnemonic")
            return []
        }

        let nativeCoins = TokensStore.TokenSelectionAssets
            .filter { $0.isNativeToken && Chain.keyImportEnabledChains.contains($0.chain) }
        logger.info("📋 Scanning \(nativeCoins.count) chains for balances")

        let results = await fetchBalancesForChains(nativeCoins: nativeCoins, wallet: wallet)
        guard !Task.isCancelled else {
            logger.warning("⚠️ Fetch cancelled")
            return []
        }

        // Store results to access derivation types later
        await MainActor.run {
            self.chainBalanceResults = results
        }

        let activeChains = convertToKeyImportChains(results: results)
        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("✨ Discovery complete! Found \(activeChains.count) active chain(s) in \(String(format: "%.2f", elapsed))s")

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

    /// Prepares chain settings for vault setup
    /// If customized, checks derivation paths for chains with alternatives
    /// Returns chain settings with correct derivation paths
    func prepareChainSettings(customized: Bool) async -> [ChainImportSetting] {
        // If customized, check derivation paths for chains with alternatives
        if customized {
            await MainActor.run { isLoading = true }
            await checkDerivationPathsForChains(chainsToImport)
        }

        // Build chain settings with derivations
        let chainSettings = chainsToImport.map { chain -> ChainImportSetting in
            let derivationPath = derivationPath(for: chain)
            // Only store non-default derivations
            if derivationPath != .default {
                return ChainImportSetting(chain: chain, derivationPath: derivationPath)
            }
            return ChainImportSetting(chain: chain)
        }

        await MainActor.run { isLoading = false }

        return chainSettings
    }

    /// Checks derivation paths for chains with alternatives and stores results
    /// Only checks chains that have alternative derivation paths defined
    private func checkDerivationPathsForChains(_ chains: [Chain]) async {
        guard let wallet = wallet else {
            logger.error("❌ Wallet not available for derivation check")
            return
        }

        // Filter to only chains that have alternative derivations
        let chainsNeedingCheck = chains.filter { alternativeDerivations[$0] != nil }

        guard !chainsNeedingCheck.isEmpty else {
            logger.info("✅ No chains require derivation path checking")
            return
        }

        logger.info("📊 Checking derivation paths for \(chainsNeedingCheck.count) chain(s) with alternatives")

        // Get native coins for chains that need checking
        let nativeCoins = TokensStore.TokenSelectionAssets
            .filter { $0.isNativeToken && chainsNeedingCheck.contains($0.chain) }

        let results = await fetchBalancesForChains(nativeCoins: nativeCoins, wallet: wallet)

        await MainActor.run {
            // Merge new results with existing ones
            // Remove old results for these chains and add new ones
            self.chainBalanceResults.removeAll { result in
                chainsNeedingCheck.contains(result.chain)
            }
            self.chainBalanceResults.append(contentsOf: results)
        }

        logger.info("✅ Derivation path check complete. Found \(results.count) results")
    }
}

// MARK: - Private Helpers

private extension KeyImportChainsSetupViewModel {
    func createWallet(from mnemonic: String) -> HDWallet? {
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            logger.error("Failed to create HDWallet from mnemonic")
            return nil
        }
        self.wallet = wallet
        return wallet
    }

    func fetchBalancesForChains(
        nativeCoins: [CoinMeta],
        wallet: HDWallet
    ) async -> [ChainBalanceResult] {
        logger.info("📊 Starting balance fetch for \(nativeCoins.count) chains concurrently")

        let allResults = await withTaskGroup(of: [ChainBalanceResult].self) { group in
            for nativeCoin in nativeCoins {
                guard !Task.isCancelled else {
                    logger.warning("⚠️ Balance fetch cancelled")
                    return [ChainBalanceResult]()
                }

                group.addTask {
                    await self.fetchBalancesForChain(nativeCoin: nativeCoin, wallet: wallet)
                }
            }

            var results = [ChainBalanceResult]()
            for await chainResults in group {
                results.append(contentsOf: chainResults)
            }
            return results
        }

        logger.info("🎉 Finished balance fetch for all chains. Found balances on \(allResults.count) derivation paths")
        return allResults
    }

    func fetchBalancesForChain(
        nativeCoin: CoinMeta,
        wallet: HDWallet
    ) async -> [ChainBalanceResult] {
        let startTime = Date()
        let chain = nativeCoin.chain
        let alternativeCount = alternativeDerivations[chain]?.count ?? 0
        let totalDerivations = 1 + alternativeCount // default + alternatives

        logger.debug("🔍 [\(chain.ticker)] Starting balance check for \(totalDerivations) derivation path(s)")

        var derivationResults = [DerivationBalanceResult]()

        // Check default derivation
        let defaultAddress = wallet.getAddressForCoin(coin: chain.coinType).description
        logger.debug("   📍 [\(chain.ticker)] Checking default derivation: \(defaultAddress)")
        let defaultResult = await fetchBalanceForDerivation(
            address: defaultAddress,
            nativeCoin: nativeCoin,
            derivationPath: nil
        )
        derivationResults.append(defaultResult)

        logger.debug("   💰 [\(chain.ticker)] Default derivation has balance: \(defaultResult.hasBalance)")

        // Check all alternative derivations for this chain
        if let alternatives = alternativeDerivations[chain] {
            for option in alternatives {
                let address = wallet.getAddressDerivation(coin: chain.coinType, derivation: option.derivation)
                logger.debug("   📍 [\(chain.ticker)] Checking \(option.derivationPath.rawValue) derivation: \(address)")
                let result = await fetchBalanceForDerivation(
                    address: address,
                    nativeCoin: nativeCoin,
                    derivationPath: option.derivationPath
                )
                derivationResults.append(result)

                logger.debug("   💰 [\(chain.ticker)] \(option.derivationPath.rawValue) has balance: \(result.hasBalance)")
            }
        }

        // Filter results to only those with balances
        let resultsWithBalance = derivationResults.filter { $0.hasBalance }

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
                nativeCoin: result.nativeCoin,
                derivationPath: result.derivationPath
            )
        }
    }

    func fetchBalanceForDerivation(
        address: String,
        nativeCoin: CoinMeta,
        derivationPath: DerivationPath?
    ) async -> DerivationBalanceResult {
        do {
            let balanceString = try await balanceService.fetchBalance(for: nativeCoin, address: address)
            guard let balance = Decimal(string: balanceString), balance > 0 else {
                return DerivationBalanceResult(nativeCoin: nativeCoin, hasBalance: false, derivationPath: derivationPath)
            }
            return DerivationBalanceResult(nativeCoin: nativeCoin, hasBalance: true, derivationPath: derivationPath)
        } catch {
            return DerivationBalanceResult(nativeCoin: nativeCoin, hasBalance: false, derivationPath: derivationPath)
        }
    }

    func convertToKeyImportChains(
        results: [ChainBalanceResult]
    ) -> [KeyImportChain] {
        // Group results by chain
        let groupedByChain = Dictionary(grouping: results) { $0.chain }

        // Convert each chain to KeyImportChain
        return groupedByChain.keys.map { chain in
            KeyImportChain(chain: chain)
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
