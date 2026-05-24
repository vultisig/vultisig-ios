//
//  QBTCClaimFeatureFlagTests.swift
//  VultisigAppTests
//
//  Locks the opt-in behaviour for QBTC claim: the workstream is off by
//  default; flipping the `qbtcEnabled` UserDefaults key (the same key
//  `SettingsViewModel.qbtcEnabled` writes to via `@AppStorage`) lights
//  it up. Surface-level gates (chain-picker visibility, navigation
//  arms) are also locked in here so a regression doesn't quietly
//  expose the flow.
//

import XCTest
@testable import VultisigApp

@MainActor
final class QBTCClaimFeatureFlagTests: XCTestCase {

    private let flagKey = "qbtcEnabled"
    private var savedFlag: Any?

    override func setUpWithError() throws {
        savedFlag = UserDefaults.standard.object(forKey: flagKey)
        UserDefaults.standard.removeObject(forKey: flagKey)
    }

    override func tearDownWithError() throws {
        if let savedFlag {
            UserDefaults.standard.set(savedFlag, forKey: flagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: flagKey)
        }
    }

    // MARK: - isFeatureEnabled

    func testFeatureFlagDefaultsToOff() {
        UserDefaults.standard.removeObject(forKey: flagKey)
        XCTAssertFalse(
            QBTCConfig.isFeatureEnabled,
            "QBTC must be opt-in — default off while the workstream is in active development"
        )
    }

    func testFeatureFlagOnReadsTrue() {
        UserDefaults.standard.set(true, forKey: flagKey)
        XCTAssertTrue(QBTCConfig.isFeatureEnabled)
    }

    func testFeatureFlagOffReadsFalse() {
        UserDefaults.standard.set(false, forKey: flagKey)
        XCTAssertFalse(QBTCConfig.isFeatureEnabled)
    }

    // MARK: - CoinSelectionViewModel chain picker gating

    func testChainPickerHidesQbtcWhenFlagOff() {
        UserDefaults.standard.set(false, forKey: flagKey)
        let vault = makeVaultWithMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        viewModel.showMldsaChainsWithoutKey = true
        viewModel.setData(for: vault, checkForSelected: false)
        XCTAssertFalse(
            viewModel.filteredChains.contains(.qbtc),
            "QBTC must not appear in the chain picker with the feature flag off"
        )
    }

    func testChainPickerShowsQbtcWhenFlagOnAndMldsaKeyPresent() {
        UserDefaults.standard.set(true, forKey: flagKey)
        let vault = makeVaultWithMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        viewModel.showMldsaChainsWithoutKey = false
        viewModel.setData(for: vault, checkForSelected: false)
        XCTAssertTrue(
            viewModel.filteredChains.contains(.qbtc),
            "QBTC must appear when the feature flag is on and the vault has an MLDSA key"
        )
    }

    func testChainPickerShowsQbtcWhenFlagOnAndShowWithoutKey() {
        // Mirrors the production path where the chain picker is invoked
        // with `showMldsaChainsWithoutKey = true` so the user can request
        // the quantum keygen by tapping QBTC even if the vault has no
        // MLDSA key yet.
        UserDefaults.standard.set(true, forKey: flagKey)
        let vault = makeVaultWithoutMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        viewModel.showMldsaChainsWithoutKey = true
        viewModel.setData(for: vault, checkForSelected: false)
        XCTAssertTrue(
            viewModel.filteredChains.contains(.qbtc),
            "QBTC must appear when the flag is on and the picker is in keygen-prompting mode"
        )
    }

    func testRequiresQuantumKeygenReturnsFalseWhenFlagOff() {
        UserDefaults.standard.set(false, forKey: flagKey)
        let vault = makeVaultWithoutMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        let qbtcAsset = makeQbtcMeta()
        XCTAssertFalse(
            viewModel.requiresQuantumKeygen(for: qbtcAsset, vault: vault),
            "With the flag off, `requiresQuantumKeygen` must return false so the keygen prompt never fires"
        )
    }

    func testRequiresQuantumKeygenReturnsTrueWhenFlagOnAndNoMldsaKey() {
        UserDefaults.standard.set(true, forKey: flagKey)
        let vault = makeVaultWithoutMLDSAKey()
        let viewModel = CoinSelectionViewModel()
        let qbtcAsset = makeQbtcMeta()
        XCTAssertTrue(
            viewModel.requiresQuantumKeygen(for: qbtcAsset, vault: vault),
            "Flag-on + no MLDSA key: the picker must surface the keygen prompt"
        )
    }

    func testRequiresQuantumKeygenReturnsFalseForNonMldsaAssetRegardlessOfFlag() {
        UserDefaults.standard.set(true, forKey: flagKey)
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
