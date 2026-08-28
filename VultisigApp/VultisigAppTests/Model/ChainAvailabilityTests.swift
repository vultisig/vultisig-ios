//
//  ChainAvailabilityTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class ChainAvailabilityTests: XCTestCase {
    func testKujiraRemainsDecodableAsHistoricalIdentity() throws {
        let decoded = try JSONDecoder().decode(Chain.self, from: Data("\"kujira\"".utf8))

        XCTAssertEqual(decoded, .kujira)
        XCTAssertTrue(Chain.allCases.contains(.kujira))
    }

    func testKujiraIsExcludedFromEveryActiveChainRoster() {
        XCTAssertFalse(Chain.kujira.isSupported)
        XCTAssertFalse(Chain.supportedCases.contains(.kujira))
        XCTAssertFalse(Chain.keyImportEnabledChains.contains(.kujira))
        XCTAssertFalse(CustomRPCSupportedChains.all.contains(.kujira))
    }

    func testKujiraHasNoActionsRoutesOrSwapCapability() {
        XCTAssertFalse(Chain.kujira.isSwapAvailable)
        XCTAssertFalse(Chain.kujira.isBuyAvailable)
        XCTAssertFalse(Chain.kujira.supportsPendingTransactions)
        XCTAssertTrue(Chain.kujira.defaultActions.isEmpty)
        XCTAssertTrue(Chain.kujira.ibcTo.isEmpty)
        XCTAssertFalse(Chain.gaiaChain.ibcTo.contains { $0.destinationChain == .kujira })
        XCTAssertFalse(Chain.osmosis.ibcTo.contains { $0.destinationChain == .kujira })
    }

    func testKujiraHasNoCatalogOrSwapKitMapping() {
        XCTAssertFalse(TokensStore.TokenSelectionAssets.contains { $0.chain == .kujira })
        XCTAssertEqual(SwapKitChainIDMapper.swapKitChainId(for: .kujira), "")
        XCTAssertNil(SwapKitChainIDMapper.chain(forSwapKitChain: "KUJI"))
    }

    func testKujiraNetworkAndSigningFactoriesRejectTheCompatibilityCase() {
        XCTAssertThrowsError(try CosmosService.getService(forChain: .kujira))
        XCTAssertThrowsError(try CosmosServiceConfig.getConfig(forChain: .kujira))
        XCTAssertThrowsError(try CosmosHelper.getHelper(forChain: .kujira))
        XCTAssertThrowsError(try CosmosHelperConfig.getConfig(forChain: .kujira))
    }

    @MainActor
    func testCoinServiceRejectsRestoringKujiraThroughAnActiveWrite() {
        let vault = Vault(name: "Compatibility test")
        let nativeKujira = CoinMeta(
            chain: .kujira,
            ticker: "KUJI",
            logo: "kuji",
            decimals: 6,
            priceProviderId: "kujira",
            contractAddress: "",
            isNativeToken: true
        )

        XCTAssertThrowsError(try CoinService.assertChainAllowed(asset: nativeKujira, vault: vault))
    }

    func testThorchainKujiraAssetsRemainAvailableForRujiFlows() {
        let retained = TokensStore.TokenSelectionAssets.filter {
            $0.chain == .thorChain && ["KUJI", "RKUJI"].contains($0.ticker.uppercased())
        }

        XCTAssertEqual(Set(retained.map { $0.ticker.uppercased() }), ["KUJI", "RKUJI"])
        XCTAssertTrue(retained.allSatisfy { $0.contractAddress.lowercased().hasPrefix("thor.") })
    }
}
