//
//  QBTCClaimFeatureFlagTests.swift
//  VultisigAppTests
//
//  Locks the shipped behaviour for QBTC claim: the workstream is enabled
//  for everyone now that the former Settings → Advanced opt-in toggle has
//  been removed. Surface-level gates (chain-picker visibility, navigation
//  arms) are also locked in here so a regression doesn't quietly hide the
//  flow.
//

import XCTest
@testable import VultisigApp

@MainActor
final class QBTCClaimFeatureFlagTests: XCTestCase {

    // MARK: - isFeatureEnabled

    func testFeatureFlagIsAlwaysEnabled() {
        XCTAssertTrue(
            QBTCConfig.isFeatureEnabled,
            "QBTC claim has shipped — the feature is always enabled"
        )
    }

    // MARK: - CoinSelectionViewModel chain picker gating

    func testChainPickerShowsQbtcWhenMldsaKeyPresent() {
        let vault = makeVaultWithMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        viewModel.showMldsaChainsWithoutKey = false
        viewModel.setData(for: vault, checkForSelected: false)
        XCTAssertTrue(
            viewModel.filteredChains.contains(.qbtc),
            "QBTC must appear when the vault has an MLDSA key"
        )
    }

    func testChainPickerShowsQbtcWhenShowWithoutKey() {
        // Mirrors the production path where the chain picker is invoked
        // with `showMldsaChainsWithoutKey = true` so the user can request
        // the quantum keygen by tapping QBTC even if the vault has no
        // MLDSA key yet.
        let vault = makeVaultWithoutMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        viewModel.showMldsaChainsWithoutKey = true
        viewModel.setData(for: vault, checkForSelected: false)
        XCTAssertTrue(
            viewModel.filteredChains.contains(.qbtc),
            "QBTC must appear when the picker is in keygen-prompting mode"
        )
    }

    func testRequiresQuantumKeygenReturnsTrueWhenNoMldsaKey() {
        let vault = makeVaultWithoutMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        let qbtcAsset = makeQbtcMeta()
        XCTAssertTrue(
            viewModel.requiresQuantumKeygen(for: qbtcAsset, vault: vault),
            "No MLDSA key: the picker must surface the keygen prompt"
        )
    }

    func testRequiresQuantumKeygenReturnsFalseForNonMldsaAsset() {
        let vault = makeVaultWithoutMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        let btcAsset = CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        XCTAssertFalse(viewModel.requiresQuantumKeygen(for: btcAsset, vault: vault))
    }

    // MARK: - Helpers

    private func makeQbtcMeta() -> CoinMeta {
        guard let meta = TokensStore.TokenSelectionAssets.first(where: {
            $0.chain == .qbtc && $0.isNativeToken
        }) else {
            return CoinMeta(
                chain: .qbtc,
                ticker: "QBTC",
                logo: "qbtc",
                decimals: 8,
                priceProviderId: "",
                contractAddress: "",
                isNativeToken: true
            )
        }
        return meta
    }

    private func makeVaultWithMLDSAKey() -> Vault {
        let vault = Vault(
            name: "QBTC Test Vault",
            signers: [],
            pubKeyECDSA: "ECDSAKey",
            pubKeyEdDSA: "EdDSAKey",
            keyshares: [],
            localPartyID: "partyID",
            hexChainCode: "hexCode",
            resharePrefix: nil,
            libType: .GG20
        )
        vault.publicKeyMLDSA44 = "mldsa44-pubkey"
        return vault
    }

    private func makeVaultWithoutMLDSAKey() -> Vault {
        Vault(
            name: "QBTC Test Vault",
            signers: [],
            pubKeyECDSA: "ECDSAKey",
            pubKeyEdDSA: "EdDSAKey",
            keyshares: [],
            localPartyID: "partyID",
            hexChainCode: "hexCode",
            resharePrefix: nil,
            libType: .GG20
        )
    }
}
