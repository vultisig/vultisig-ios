//
//  ThorchainLPPoolCatalogTests.swift
//  VultisigAppTests
//
//  Which pools are offered, and which asset each one deposits. Both answers
//  decide what leaves the wallet, so both are pinned.
//

import XCTest
@testable import VultisigApp

final class ThorchainLPPoolCatalogTests: XCTestCase {

    private let pools = [
        AddLPFixture.pool(AddLPFixture.ethPool),
        AddLPFixture.pool(AddLPFixture.usdcPool),
        AddLPFixture.pool(AddLPFixture.btcPool)
    ]

    func testOnlyTheChainsOwnPoolsAreOffered() {
        let offered = ThorchainLPPoolCatalog.depositablePools(
            on: .ethereum,
            pools: pools,
            holdings: [AddLPFixture.ether(), AddLPFixture.usdc(), AddLPFixture.bitcoin()]
        )

        XCTAssertEqual(offered.map(\.thorchainAsset), [AddLPFixture.ethPool, AddLPFixture.usdcPool])
    }

    /// ⚠️ A pool whose asset the vault does not hold is not an option.
    ///
    /// The dropdown this replaces listed every pool on the chain and then
    /// silently declined to switch the source asset when the vault held no such
    /// token — leaving the previously selected asset paying for a memo naming a
    /// different one.
    func testAPoolTheVaultCannotFundIsNotOffered() {
        let offered = ThorchainLPPoolCatalog.depositablePools(
            on: .ethereum,
            pools: pools,
            holdings: [AddLPFixture.ether()]
        )

        XCTAssertEqual(offered.map(\.thorchainAsset), [AddLPFixture.ethPool])
    }

    /// The memo needs the contract-suffixed name; the row shows the asset.
    func testAnOfferedPoolCarriesItsFullThorchainName() throws {
        let offered = ThorchainLPPoolCatalog.depositablePools(
            on: .ethereum,
            pools: [AddLPFixture.pool(AddLPFixture.usdcPool)],
            holdings: [AddLPFixture.ether(), AddLPFixture.usdc()]
        )
        let entry = try XCTUnwrap(offered.first)

        XCTAssertEqual(entry.thorchainAsset, AddLPFixture.usdcPool)
        XCTAssertEqual(entry.asset.ticker, "USDC")
        XCTAssertFalse(entry.asset.isNativeToken)
    }

    func testANativePoolResolvesTheChainsNativeCoin() throws {
        let coin = try XCTUnwrap(
            ThorchainLPPoolCatalog.depositCoin(
                forPool: AddLPFixture.ethPool,
                in: [AddLPFixture.ether(), AddLPFixture.usdc()]
            )
        )

        XCTAssertEqual(coin.ticker, "ETH")
        XCTAssertTrue(coin.isNativeToken)
    }

    func testATokenPoolResolvesTheTokenNotTheNativeCoin() throws {
        let coin = try XCTUnwrap(
            ThorchainLPPoolCatalog.depositCoin(
                forPool: AddLPFixture.usdcPool,
                in: [AddLPFixture.ether(), AddLPFixture.usdc()]
            )
        )

        XCTAssertEqual(coin.ticker, "USDC")
        XCTAssertFalse(coin.isNativeToken)
    }

    /// ⚠️ Matched on chain AND ticker. On ticker alone, `ETH.USDC` would
    /// resolve to a USDC the vault holds on another chain — a wrong-asset,
    /// wrong-chain transfer rather than a wrong screen.
    func testAPoolNeverResolvesTheSameTickerOnAnotherChain() {
        let baseUSDC = FunctionCallFixture.makeCoin(
            .base,
            ticker: "USDC",
            decimals: 6,
            isNative: false,
            address: "0xbase"
        )

        XCTAssertNil(
            ThorchainLPPoolCatalog.depositCoin(forPool: AddLPFixture.usdcPool, in: [baseUSDC])
        )
    }

    /// ⚠️ A ticker is not an identity. THORChain names a token pool
    /// `ETH.USDC-0X<contract>`, and that contract is what makes it *the* USDC
    /// pool. A vault can hold a second token calling itself USDC on the same
    /// chain; picking it would transfer the wrong token against a memo naming
    /// the real pool, and THORChain would credit nothing.
    func testATokenPoolResolvesTheContractItNamesNotJustTheTicker() {
        let impostor = FunctionCallFixture.makeCoin(
            .ethereum,
            ticker: "USDC",
            decimals: 6,
            isNative: false,
            address: "0xsender"
        )
        impostor.contractAddress = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

        XCTAssertNil(
            ThorchainLPPoolCatalog.depositCoin(forPool: AddLPFixture.usdcPool, in: [impostor]),
            "a same-ticker token at another contract is a different token"
        )
        XCTAssertEqual(
            ThorchainLPPoolCatalog.depositCoin(
                forPool: AddLPFixture.usdcPool,
                in: [impostor, AddLPFixture.usdc()]
            )?.contractAddress.uppercased(),
            AddLPFixture.usdcPool.split(separator: "-").last.map(String.init)
        )
    }

    /// The contract is compared case-insensitively: THORChain upper-cases the
    /// hex, the wallet stores it lower-cased.
    func testAContractMatchIsCaseInsensitive() {
        XCTAssertNotNil(
            ThorchainLPPoolCatalog.depositCoin(
                forPool: "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                in: [AddLPFixture.usdc()]
            )
        )
    }

    /// ⚠️ A pool with no contract suffix is the chain's own asset, so it must
    /// never resolve a token sharing the ticker.
    func testANativePoolNeverResolvesAToken() {
        let fakeNative = FunctionCallFixture.makeCoin(
            .ethereum,
            ticker: "ETH",
            decimals: 18,
            isNative: false,
            address: "0xsender"
        )
        fakeNative.contractAddress = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

        XCTAssertNil(ThorchainLPPoolCatalog.depositCoin(forPool: AddLPFixture.ethPool, in: [fakeNative]))
        XCTAssertNotNil(
            ThorchainLPPoolCatalog.depositCoin(forPool: AddLPFixture.ethPool, in: [fakeNative, AddLPFixture.ether()])
        )
    }

    /// The offered list inherits the same rule.
    func testAPoolIsNotOfferedWhenOnlyAnImpostorTokenMatchesTheTicker() {
        let impostor = FunctionCallFixture.makeCoin(
            .ethereum,
            ticker: "USDC",
            decimals: 6,
            isNative: false,
            address: "0xsender"
        )
        impostor.contractAddress = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

        let offered = ThorchainLPPoolCatalog.depositablePools(
            on: .ethereum,
            pools: [AddLPFixture.pool(AddLPFixture.usdcPool)],
            holdings: [impostor]
        )

        XCTAssertTrue(offered.isEmpty)
    }

    func testAMalformedPoolNameResolvesNothing() {
        XCTAssertNil(ThorchainLPPoolCatalog.depositCoin(forPool: "ETH", in: [AddLPFixture.ether()]))
        XCTAssertNil(ThorchainLPPoolCatalog.depositCoin(forPool: "", in: [AddLPFixture.ether()]))
    }
}
