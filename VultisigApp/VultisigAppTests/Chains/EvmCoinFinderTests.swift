//
//  EvmCoinFinderTests.swift
//  VultisigApp
//
//  Pins the legitimacy-filter invariants for the 1inch-based EVM token
//  discovery path that replaced the Alchemy heuristic blocklist (see #4334).
//

@testable import VultisigApp
import XCTest

final class EvmCoinFinderTests: XCTestCase {

    // MARK: - Filter primitive

    func testCoinGeckoVerifiedTrueWhenProvidersIncludeCoinGecko() {
        let token = OneInchToken(
            address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            symbol: "USDC",
            name: "USD Coin",
            decimals: 6,
            logoURI: "https://tokens.1inch.io/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48.png",
            providers: ["1inch", "CoinGecko", "Uniswap Labs Default"]
        )
        XCTAssertTrue(token.isCoinGeckoVerified)
    }

    func testCoinGeckoVerifiedFalseWhenProvidersOmitCoinGecko() {
        // Real-world example: a sketchy airdrop token that 1inch knows about
        // but CoinGecko hasn't curated. Has metadata but no allowlist signal.
        let token = OneInchToken(
            address: "0x00000000002514bf58ae82408e1e217f16a1dfa0",
            symbol: "ANON",
            name: "Anon",
            decimals: 18,
            logoURI: nil,
            providers: ["1inch"]
        )
        XCTAssertFalse(token.isCoinGeckoVerified)
    }

    func testCoinGeckoVerifiedFalseWhenProvidersNil() {
        let token = OneInchToken(
            address: "0xdeadbeef00000000000000000000000000000000",
            symbol: "X",
            name: "X",
            decimals: 18,
            logoURI: nil,
            providers: nil
        )
        XCTAssertFalse(token.isCoinGeckoVerified)
    }

    // MARK: - Chain support

    func testEthereumSupportedChainsMatchSdkResolver() {
        // Mirrors `vultisig-sdk/.../find/resolvers/evm/index.ts:20-28` —
        // changing this set requires changing the SDK in lockstep.
        XCTAssertTrue(EvmCoinFinder.isSupported(chain: .ethereum))
        XCTAssertTrue(EvmCoinFinder.isSupported(chain: .base))
        XCTAssertTrue(EvmCoinFinder.isSupported(chain: .arbitrum))
        XCTAssertTrue(EvmCoinFinder.isSupported(chain: .polygon))
        XCTAssertTrue(EvmCoinFinder.isSupported(chain: .polygonV2))
        XCTAssertTrue(EvmCoinFinder.isSupported(chain: .optimism))
        XCTAssertTrue(EvmCoinFinder.isSupported(chain: .bscChain))
        XCTAssertTrue(EvmCoinFinder.isSupported(chain: .avalanche))
    }

    func testUnsupportedChainsFallThroughToTokensStore() {
        // These EVM chains have no 1inch /balance + /token surface, so the
        // dispatcher in `EvmServiceConfig.TokenProvider.standard` falls back
        // to `EvmServiceStruct.getTokensFallback` (TokensStore iteration).
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .blast))
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .cronosChain))
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .zksync))
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .mantle))
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .hyperliquid))
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .sei))
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .tron))
    }

    func testNonEvmChainsNotSupported() {
        // Sanity: only EVM chains belong on this list — Solana/Cardano/etc.
        // have their own discovery paths.
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .solana))
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .cardano))
        XCTAssertFalse(EvmCoinFinder.isSupported(chain: .bitcoin))
    }
}
