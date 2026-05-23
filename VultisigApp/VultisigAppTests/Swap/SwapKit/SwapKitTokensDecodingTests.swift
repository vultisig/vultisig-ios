//
//  SwapKitTokensDecodingTests.swift
//  VultisigAppTests
//
//  Wire-format + adapter coverage for `GET /tokens?provider=<NAME>`. Drives
//  off the trimmed NEAR fixture (vendored at `__fixtures__/03-tokens-NEAR.json`)
//  which covers a mix of Vultisig-supported chains (ARB, AVAX, BASE, BCH,
//  BSC, DASH, LTC, OP, TON, TRON) and unsupported ones (BERA, GNO, MONAD,
//  STRK, XLAYER) so the chain reverse-mapper drop is exercised.
//

import XCTest
@testable import VultisigApp

final class SwapKitTokensDecodingTests: XCTestCase {

    func testDecodesEnvelope() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitTokensResponse.self,
            from: "03-tokens-NEAR"
        )
        XCTAssertEqual(response.provider, "NEAR")
        XCTAssertEqual(response.tokens.count, response.count)
        XCTAssertFalse(response.tokens.isEmpty)
    }

    func testGasTokensHaveNoUsableContract() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitTokensResponse.self,
            from: "03-tokens-NEAR"
        )
        // At least one gas token survives the reverse-mapper drop. Verify
        // its CoinMeta is `isNativeToken: true` with empty contract.
        let bscNative = response.tokens.first {
            $0.chain == "BSC" && ($0.address?.isEmpty ?? true)
        }
        let coinMeta = try XCTUnwrap(bscNative?.toCoinMeta())
        XCTAssertTrue(coinMeta.isNativeToken)
        XCTAssertEqual(coinMeta.contractAddress, "")
        XCTAssertEqual(coinMeta.chain, .bscChain)
    }

    func testEVMContractTokenAdapts() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitTokensResponse.self,
            from: "03-tokens-NEAR"
        )
        // Any contract-bearing EVM token (ARB / BASE / BSC / AVAX / OP)
        // must adapt with `isNativeToken: false` + a populated 0x... contract.
        let evmContract = response.tokens.first { token in
            guard let chain = SwapKitChainIDMapper.chain(forSwapKitChain: token.chain),
                  chain.chainType == .EVM else { return false }
            return !(token.address?.isEmpty ?? true)
        }
        let coinMeta = try XCTUnwrap(evmContract?.toCoinMeta())
        XCTAssertFalse(coinMeta.isNativeToken)
        XCTAssertTrue(coinMeta.contractAddress.lowercased().hasPrefix("0x"))
        XCTAssertEqual(coinMeta.contractAddress.count, 42)
    }

    func testUnsupportedChainsAreDropped() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitTokensResponse.self,
            from: "03-tokens-NEAR"
        )
        let dropped: Set<String> = ["BERA", "GNO", "MONAD", "STRK", "XLAYER"]
        for token in response.tokens where dropped.contains(token.chain) {
            XCTAssertNil(
                token.toCoinMeta(),
                "Chain \(token.chain) must drop via reverse mapper — token: \(token.identifier)"
            )
        }
    }

    func testTronWrapperContractIsDropped() throws {
        // SwapKit-via-NEAR's TRON.USDT comes through with a contract that's
        // a real Tron base58 address, but the reverse-mapper's `chainType`
        // default-arm conservatively rejects non-EVM/Solana contracts.
        // Pinned so a future relaxation re-runs this test.
        let tronToken = SwapKitToken(
            chain: "TRON",
            chainId: "728126428",
            address: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
            ticker: "USDT",
            identifier: "TRON.USDT-TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
            name: "Tether",
            decimals: 6,
            logoURI: nil,
            coingeckoId: "tether"
        )
        XCTAssertNil(tronToken.toCoinMeta())
    }

    func testNearChainTokensAreDropped() throws {
        // NEAR chain itself isn't supported as a Vultisig wallet — even
        // gas-token NEAR.NEAR must not adapt.
        let nearGas = SwapKitToken(
            chain: "NEAR",
            chainId: "near",
            address: "",
            ticker: "NEAR",
            identifier: "NEAR.NEAR",
            name: "NEAR Protocol",
            decimals: 24,
            logoURI: nil,
            coingeckoId: "near"
        )
        XCTAssertNil(nearGas.toCoinMeta())
    }

    func testMergeByChainDedupesByIdentifier() throws {
        // Two responses both list ETH.USDT — merged bucket has one entry.
        let payload = """
        [
          {
            "provider": "ONEINCH",
            "count": 2,
            "tokens": [
              {"chain":"ETH","chainId":"1","address":"0xdAC17F958D2ee523a2206206994597C13D831ec7","ticker":"USDT","identifier":"ETH.USDT-0xdAC17F958D2ee523a2206206994597C13D831ec7","name":"Tether","decimals":6,"logoURI":"","coingeckoId":"tether"},
              {"chain":"ETH","chainId":"1","address":"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48","ticker":"USDC","identifier":"ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48","name":"USDC","decimals":6,"logoURI":"","coingeckoId":"usd-coin"}
            ]
          },
          {
            "provider": "NEAR",
            "count": 1,
            "tokens": [
              {"chain":"ETH","chainId":"1","address":"0xdAC17F958D2ee523a2206206994597C13D831ec7","ticker":"USDT","identifier":"ETH.USDT-0xdAC17F958D2ee523a2206206994597C13D831ec7","name":"Tether","decimals":6,"logoURI":"","coingeckoId":"tether"}
            ]
          }
        ]
        """.data(using: .utf8) ?? Data()
        let responses = try JSONDecoder().decode([SwapKitTokensResponse].self, from: payload)
        let buckets = SwapKitTokensCache.mergeByChain(responses: responses)
        let eth = try XCTUnwrap(buckets[.ethereum])
        XCTAssertEqual(eth.tokens.count, 2)
        let usdtMatches = eth.tokens.filter { $0.ticker == "USDT" }
        XCTAssertEqual(
            usdtMatches.count, 1,
            "USDT must be present exactly once after dedup"
        )
    }
}
