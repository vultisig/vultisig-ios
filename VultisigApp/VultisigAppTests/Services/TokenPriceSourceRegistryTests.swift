//
//  TokenPriceSourceRegistryTests.swift
//  VultisigAppTests
//
//  Locks the per-chain routing extracted from the old 5-branch
//  `CryptoPriceService.fetchPrices(contracts:chain:)`: each chain family must
//  resolve to its dedicated price source, and the CoinGecko platform table must
//  match the EVM-only mapping the previous switch encoded.
//

import XCTest
@testable import VultisigApp

final class TokenPriceSourceRegistryTests: XCTestCase {

    // MARK: - Registry routing

    func test_registry_routesSolanaToSolanaSource() {
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .solana) is SolanaTokenPriceSource)
    }

    func test_registry_routesSuiToSuiSource() {
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .sui) is SuiTokenPriceSource)
    }

    func test_registry_routesMayaToMayaSource() {
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .mayaChain) is MayaChainTokenPriceSource)
    }

    func test_registry_routesThorChainFamilyToThorSource() {
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .thorChain) is ThorChainTokenPriceSource)
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .thorChainChainnet) is ThorChainTokenPriceSource)
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .thorChainStagenet) is ThorChainTokenPriceSource)
    }

    func test_registry_routesEvmChainsToCoinGeckoSource() {
        // A representative EVM chain and a non-pool L1 both fall through to the
        // CoinGecko-by-contract + LiFi default source.
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .ethereum) is CoinGeckoContractTokenPriceSource)
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .base) is CoinGeckoContractTokenPriceSource)
    }

    func test_registry_routesNonPoolChainsToCoinGeckoSource() {
        // Chains without a dedicated pool source (e.g. Bitcoin) still resolve to
        // the CoinGecko default, matching the old `else` branch.
        XCTAssertTrue(TokenPriceSourceRegistry.source(for: .bitcoin) is CoinGeckoContractTokenPriceSource)
    }

    // MARK: - CoinGecko platform table (EVM-only) matches the old switch

    func test_coinGeckoPlatform_evmChainsMapToTheirPlatformIds() {
        XCTAssertEqual(CoinGeckoPlatform.id(for: .ethereum), "ethereum")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .ethereumSepolia), "ethereum")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .avalanche), "avalanche")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .base), "base")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .blast), "blast")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .arbitrum), "arbitrum-one")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .polygon), "polygon-pos")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .polygonV2), "polygon-pos")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .optimism), "optimistic-ethereum")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .bscChain), "binance-smart-chain")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .zksync), "zksync")
        XCTAssertEqual(CoinGeckoPlatform.id(for: .mantle), "mantle")
    }

    func test_coinGeckoPlatform_nonEvmChainsMapToEmpty() {
        XCTAssertEqual(CoinGeckoPlatform.id(for: .thorChain), .empty)
        XCTAssertEqual(CoinGeckoPlatform.id(for: .mayaChain), .empty)
        XCTAssertEqual(CoinGeckoPlatform.id(for: .solana), .empty)
        XCTAssertEqual(CoinGeckoPlatform.id(for: .sui), .empty)
        XCTAssertEqual(CoinGeckoPlatform.id(for: .bitcoin), .empty)
    }
}
