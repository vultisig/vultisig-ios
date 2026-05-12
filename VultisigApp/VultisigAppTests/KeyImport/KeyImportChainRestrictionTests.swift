//
//  KeyImportChainRestrictionTests.swift
//  VultisigAppTests
//
//  Covers the rule that key-import vaults can only operate on chains whose
//  per-chain TSS shares were derived during import:
//    - `Vault.availableChains` returns `chainPublicKeys` for KeyImport vaults.
//    - `CoinService.assertChainAllowed` rejects writes to other chains.
//    - `CoinSelectionViewModel.filterChains(.swap, vault:)` restricts the
//      swap chain picker accordingly.
//

import XCTest
@testable import VultisigApp

@MainActor
final class KeyImportChainRestrictionTests: XCTestCase {

    // MARK: - Vault.availableChains

    func testAvailableChains_keyImportVault_returnsChainPublicKeys() {
        let vault = makeKeyImportVault(chains: [.thorChain])
        XCTAssertEqual(vault.availableChains, [.thorChain])
    }

    func testAvailableChains_keyImportVault_ignoresCoinsNotInChainPublicKeys() {
        // Simulate the bug we're fixing: a stray ETH coin sneaks in even though
        // the user only enabled THORChain at import. `availableChains` must
        // still reflect the user's selection, not the drifted coin set.
        let vault = makeKeyImportVault(chains: [.thorChain])
        vault.coins.append(makeNativeCoin(chain: .ethereum))

        XCTAssertEqual(vault.availableChains, [.thorChain])
    }

    func testAvailableChains_dklsVault_returnsAllChains() {
        let vault = Vault(name: "DKLS", libType: .DKLS)
        XCTAssertEqual(vault.availableChains.count, Chain.allCases.count)
    }

    func testAvailableChains_keyImportLegacyVault_fallsBackToCoinDerivedChains() {
        // Legacy JSON backups predate `chainPublicKeys` persistence. A vault
        // restored from that format has libType=KeyImport but an empty
        // chainPublicKeys list. We must not soft-brick the restored vault:
        // fall back to coin-derived chains so it keeps working.
        let vault = Vault(name: "LegacyKeyImport", libType: .KeyImport)
        vault.chainPublicKeys = []
        vault.coins.append(makeNativeCoin(chain: .thorChain))

        XCTAssertEqual(vault.availableChains, [.thorChain])
    }

    func testAssertChainAllowed_keyImportLegacyVault_doesNotBlockWrites() {
        let vault = Vault(name: "LegacyKeyImport", libType: .KeyImport)
        vault.chainPublicKeys = []
        let ethMeta = makeMeta(chain: .ethereum, ticker: "ETH", isNative: true)

        XCTAssertNoThrow(try CoinService.assertChainAllowed(asset: ethMeta, vault: vault))
    }

    // MARK: - CoinService.assertChainAllowed

    func testAssertChainAllowed_keyImportVault_throwsForUnauthorizedChain() {
        let vault = makeKeyImportVault(chains: [.thorChain])
        let ethMeta = makeMeta(chain: .ethereum, ticker: "ETH", isNative: true)

        XCTAssertThrowsError(try CoinService.assertChainAllowed(asset: ethMeta, vault: vault)) { error in
            guard let coinError = error as? CoinServiceError else {
                return XCTFail("Expected CoinServiceError, got \(error)")
            }
            XCTAssertEqual(coinError, .chainNotEnabledForKeyImport(.ethereum))
        }
    }

    func testAssertChainAllowed_keyImportVault_allowsEnabledChain() throws {
        let vault = makeKeyImportVault(chains: [.thorChain])
        let runeMeta = makeMeta(chain: .thorChain, ticker: "RUNE", isNative: true)

        XCTAssertNoThrow(try CoinService.assertChainAllowed(asset: runeMeta, vault: vault))
    }

    func testAssertChainAllowed_dklsVault_allowsAnyChain() throws {
        let vault = Vault(name: "DKLS", libType: .DKLS)
        let ethMeta = makeMeta(chain: .ethereum, ticker: "ETH", isNative: true)

        XCTAssertNoThrow(try CoinService.assertChainAllowed(asset: ethMeta, vault: vault))
    }

    // MARK: - CoinService.addToChain (full path)

    func testAddToChain_keyImportVault_throwsForUnauthorizedChain() {
        let vault = makeKeyImportVault(chains: [.thorChain])
        let ethMeta = makeMeta(chain: .ethereum, ticker: "ETH", isNative: true)
        let initialCoinCount = vault.coins.count

        XCTAssertThrowsError(try CoinService.addToChain(asset: ethMeta, to: vault, priceProviderId: nil)) { error in
            XCTAssertEqual(error as? CoinServiceError, .chainNotEnabledForKeyImport(.ethereum))
        }
        XCTAssertEqual(vault.coins.count, initialCoinCount, "Vault coins must not grow when a chain is rejected")
    }

    // MARK: - CoinSelectionViewModel.filterChains

    func testFilterChains_swap_keyImportVault_restrictsToChainPublicKeys() {
        let vault = makeKeyImportVault(chains: [.thorChain])
        // Stage the bug: an ETH native coin already exists on the vault.
        // The swap picker must still hide it because ETH was not enabled at import.
        vault.coins.append(makeNativeCoin(chain: .ethereum))
        vault.coins.append(makeNativeCoin(chain: .thorChain))

        let viewModel = CoinSelectionViewModel()
        viewModel.setData(for: vault, checkForSelected: false)

        let chains = viewModel.filterChains(type: .swap, vault: vault)

        XCTAssertTrue(chains.contains(.thorChain), "THORChain (enabled at import) must be selectable")
        XCTAssertFalse(chains.contains(.ethereum), "Ethereum (not enabled at import) must be filtered out")
    }

    func testFilterChains_swap_dklsVault_unaffectedByKeyImportFilter() {
        let vault = Vault(name: "DKLS", libType: .DKLS)
        vault.coins.append(makeNativeCoin(chain: .ethereum))
        vault.coins.append(makeNativeCoin(chain: .thorChain))

        let viewModel = CoinSelectionViewModel()
        viewModel.setData(for: vault, checkForSelected: false)

        let chains = viewModel.filterChains(type: .swap, vault: vault)

        // DKLS vault: the existing `vault.chains` filter still requires native
        // coins, but the new `availableChains` filter is a no-op (allCases).
        XCTAssertTrue(chains.contains(.thorChain))
        XCTAssertTrue(chains.contains(.ethereum))
    }

    // MARK: - Helpers

    private func makeKeyImportVault(chains: [Chain]) -> Vault {
        let vault = Vault(name: "KeyImport", libType: .KeyImport)
        vault.pubKeyECDSA = "ecdsa-root"
        vault.pubKeyEdDSA = "eddsa-root"
        vault.hexChainCode = "00"
        vault.chainPublicKeys = chains.map { chain in
            ChainPublicKey(
                chain: chain,
                publicKeyHex: "pub-\(chain.name)",
                isEddsa: chain.signingKeyType == .EdDSA
            )
        }
        // Mirror what `setDefaultCoinsOnce` would produce post-import: each
        // enabled chain gets its native coin.
        for chain in chains {
            vault.coins.append(makeNativeCoin(chain: chain))
        }
        return vault
    }

    private func makeMeta(chain: Chain, ticker: String, isNative: Bool) -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: isNative
        )
    }

    private func makeNativeCoin(chain: Chain) -> Coin {
        let meta = makeMeta(chain: chain, ticker: chain.ticker, isNative: true)
        return Coin(asset: meta, address: "addr-\(chain.name)", hexPublicKey: "pub-\(chain.name)")
    }
}
