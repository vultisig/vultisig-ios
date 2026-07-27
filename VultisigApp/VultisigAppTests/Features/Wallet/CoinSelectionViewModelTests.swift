//
//  CoinSelectionViewModelTests.swift
//  VultisigAppTests
//
//  Parity guard for the migration of `CoinSelectionViewModel.groupAssets` off a
//  direct `TokensStore.TokenSelectionAssets` read onto the catalog's bundled
//  provider (`BundledTokensProvider`). The grouped output must be byte-identical
//  to the pre-migration algorithm — same curated set, same per-chain ordering
//  (native first), same sepolia / thorchain-chainnet / QBTC-MLDSA gates.
//

import XCTest
@testable import VultisigApp

@MainActor
final class CoinSelectionViewModelTests: XCTestCase {

    // The pre-migration algorithm, reproduced verbatim, as the parity reference.
    private func legacyGroupedAssets(
        for vault: Vault,
        showMldsaChainsWithoutKey: Bool
    ) -> [Chain: [CoinMeta]] {
        let enableETHSepolia = UserDefaults.standard.bool(forKey: "sepolia")
        let enableThorchainChainnet = UserDefaults.standard.bool(forKey: "thorchainChainnet")
        let hasMLDSAKey = vault.publicKeyMLDSA44 != nil && !(vault.publicKeyMLDSA44 ?? "").isEmpty

        let filteredAssets = TokensStore.TokenSelectionAssets.filter { asset in
            if asset.chain == .ethereumSepolia { return enableETHSepolia }
            if asset.chain == .thorChainChainnet { return enableThorchainChainnet }
            if asset.chain == .thorChainStagenet { return enableThorchainChainnet }
            if asset.chain.signingKeyType == .MLDSA {
                guard QBTCConfig.isFeatureEnabled else { return false }
                return hasMLDSAKey || showMldsaChainsWithoutKey
            }
            return true
        }

        var grouped = Dictionary(grouping: filteredAssets.sorted(by: { first, _ in
            first.isNativeToken
        })) { $0.chain }

        if enableETHSepolia {
            grouped[TokensStore.Token.ethSepolia.chain] = [TokensStore.Token.ethSepolia]
        }
        return grouped
    }

    private func idMap(_ grouped: [Chain: [CoinMeta]]) -> [Chain: [String]] {
        grouped.mapValues { $0.map(\.uniqueId) }
    }

    /// Order-sensitive, whole-dictionary parity against the legacy algorithm.
    func testGroupAssetsMatchesLegacyAlgorithm() {
        let vault = Vault.example
        let viewModel = CoinSelectionViewModel()

        viewModel.setData(for: vault, checkForSelected: false)

        let expected = legacyGroupedAssets(for: vault, showMldsaChainsWithoutKey: false)
        XCTAssertEqual(idMap(viewModel.groupedAssets), idMap(expected))
    }

    /// Same parity when the caller opts into showing MLDSA chains before keygen.
    func testGroupAssetsMatchesLegacyAlgorithmShowingMldsaChains() {
        let vault = Vault.example
        let viewModel = CoinSelectionViewModel()
        viewModel.showMldsaChainsWithoutKey = true

        viewModel.setData(for: vault, checkForSelected: false)

        let expected = legacyGroupedAssets(for: vault, showMldsaChainsWithoutKey: true)
        XCTAssertEqual(idMap(viewModel.groupedAssets), idMap(expected))
    }

    /// A curated (bundled-only) chain surfaces exactly its `TokensStore` set.
    func testCuratedChainSurfacesExactTokensStoreSet() {
        let viewModel = CoinSelectionViewModel()
        viewModel.setData(for: .example, checkForSelected: false)

        for chain in [Chain.ethereum, .bitcoin, .thorChain, .solana] {
            let expected = TokensStore.TokenSelectionAssets.filter { $0.chain == chain }
            XCTAssertEqual(
                Set(viewModel.groupedAssets[chain]?.map(\.uniqueId) ?? []),
                Set(expected.map(\.uniqueId)),
                "\(chain) should surface exactly its curated TokensStore tokens"
            )
        }
    }

    /// The native token sorts first within every surfaced chain group.
    func testNativeTokenIsFirstInEachGroup() {
        let viewModel = CoinSelectionViewModel()
        viewModel.setData(for: .example, checkForSelected: false)

        for (chain, tokens) in viewModel.groupedAssets {
            guard tokens.contains(where: { $0.isNativeToken }) else { continue }
            XCTAssertTrue(
                tokens.first?.isNativeToken == true,
                "\(chain) group must lead with its native token"
            )
        }
    }

    /// Sepolia is gated off by default (flag absent), matching the provider gate.
    func testSepoliaGatedOffByDefault() {
        let suiteName = "CoinSelectionViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Provider gate is the single source of truth for chain visibility.
        XCTAssertTrue(
            BundledTokensProvider.curatedTokens(for: .ethereumSepolia, defaults: defaults).isEmpty
        )
    }
}
