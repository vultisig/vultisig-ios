//
//  BlockaidSolanaSimulationParserTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

final class BlockaidSolanaSimulationParserTests: XCTestCase {

    // MARK: - Decode

    /// Regression guard: Blockaid serialises Solana `raw_value` as a JSON number
    /// even though the extension's TS type claims string. The strict Swift
    /// decoder must accept both forms. Captured body is trimmed from a real
    /// Jupiter swap response.
    func test_decode_numericRawValue() throws {
        let json = """
        {
          "encoding": "base58",
          "status": "Success",
          "result": {
            "simulation": {
              "account_summary": {
                "account_assets_diff": [
                  {
                    "asset": { "type": "SOL", "name": "SOL", "symbol": "SOL", "decimals": 9, "logo": "x" },
                    "in": null,
                    "out": { "usd_price": 5.94, "summary": "Lost", "value": 0.067, "raw_value": 67498185 },
                    "asset_type": "SOL"
                  },
                  {
                    "asset": { "type": "TOKEN", "name": "USD Coin", "symbol": "USDC", "address": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "decimals": 6, "logo": "y" },
                    "in": null,
                    "out": { "usd_price": 0.91, "summary": "Lost", "value": 0.91, "raw_value": 910724 },
                    "asset_type": "TOKEN"
                  }
                ]
              }
            },
            "validation": null
          },
          "error": null,
          "request_id": "r"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BlockaidSolanaSimulationResponseJson.self, from: data)

        let diffs = decoded.result?.simulation?.accountSummary?.accountAssetsDiff
        XCTAssertEqual(diffs?.count, 2)
        XCTAssertEqual(diffs?[0].out?.rawValue, "67498185")
        XCTAssertEqual(diffs?[1].out?.rawValue, "910724")
    }

    /// When Blockaid returns a validation block alongside simulation, the
    /// response should produce a SecurityScannerResult so the "Scanned by
    /// Blockaid" header can render. Null validation returns nil (header
    /// stays in .idle).
    func test_toKeysignScannerResult_returnsResult_whenValidationPresent() throws {
        let json = """
        {
          "result": {
            "simulation": null,
            "validation": {
              "result_type": "Benign",
              "reason": "",
              "features": [],
              "extended_features": []
            }
          },
          "status": "Success"
        }
        """
        let decoded = try JSONDecoder().decode(
            BlockaidSolanaSimulationResponseJson.self,
            from: json.data(using: .utf8)!
        )
        let scannerResult = decoded.toKeysignScannerResult()
        XCTAssertNotNil(scannerResult)
        XCTAssertEqual(scannerResult?.provider, "blockaid")
        XCTAssertTrue(scannerResult?.isSecure ?? false)
    }

    func test_toKeysignScannerResult_returnsNil_whenValidationMissing() {
        let response = BlockaidSolanaSimulationResponseJson(
            result: BlockaidSolanaSimulationResponseJson.BlockaidSolanaSimulationResultJson(
                simulation: nil,
                validation: nil
            ),
            status: "Success",
            error: nil
        )
        XCTAssertNil(response.toKeysignScannerResult())
    }

    // MARK: - Short-circuit paths

    func test_parseSolana_returnsNil_whenResultMissing() {
        let response = BlockaidSolanaSimulationResponseJson(result: nil, status: "Success", error: nil)
        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response))
    }

    func test_parseSolana_returnsNil_whenSimulationMissing() {
        let response = BlockaidSolanaSimulationResponseJson(
            result: BlockaidSolanaSimulationResponseJson.BlockaidSolanaSimulationResultJson(simulation: nil, validation: nil),
            status: "Success",
            error: nil
        )
        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response))
    }

    func test_parseSolana_returnsNil_whenDiffsEmpty() {
        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response(with: [])))
    }

    // MARK: - Transfer

    func test_parseSolana_transfer_returnsTransferInfo() {
        let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        let diff = diff(
            asset: token(symbol: "USDC", address: usdcMint, decimals: 6),
            out: balance("1500000")
        )
        let info = BlockaidSimulationParser.parseSolana(response: response(with: [diff]))

        guard case let .transfer(coin, amount) = info else {
            return XCTFail("expected .transfer, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.ticker, "USDC")
        XCTAssertEqual(coin.address, usdcMint)
        XCTAssertEqual(coin.decimals, 6)
        XCTAssertEqual(coin.chain, .solana)
        XCTAssertEqual(amount, BigInt("1500000"))
    }

    /// Native SOL carries `type == "SOL"` with a nil mint; the parser should
    /// substitute the wrapped-SOL mint sentinel to keep downstream lookups
    /// uniform.
    func test_parseSolana_transfer_nativeSOL_usesWrappedSolMint() {
        let diff = diff(
            asset: native(symbol: "SOL", decimals: 9),
            out: balance("2000000000") // 2 SOL
        )
        let info = BlockaidSimulationParser.parseSolana(response: response(with: [diff]))

        guard case let .transfer(coin, amount) = info else {
            return XCTFail("expected .transfer, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.address, BlockaidSimulationParser.wrappedSolMint)
        XCTAssertEqual(coin.ticker, "SOL")
        XCTAssertEqual(amount, BigInt("2000000000"))
    }

    /// Native SOL must render the chain's own logo, not the wrapped-SOL
    /// (WSOL) metadata that `TokensStore` returns for the wrapped-SOL mint,
    /// and not the Blockaid per-request CDN URL (which isn't hot-linkable).
    func test_parseSolana_transfer_nativeSOL_logoIsChainNativeAsset() {
        let diff = diff(
            asset: BlockaidSolanaSimulationJson.Asset(
                type: "SOL",
                name: "Solana",
                symbol: "SOL",
                address: nil,
                decimals: 9,
                logo: "https://cdn.blockaid.io/ephemeral/will-not-resolve"
            ),
            out: balance("1000000000")
        )
        let info = BlockaidSimulationParser.parseSolana(response: response(with: [diff]))

        guard case let .transfer(coin, _) = info else {
            return XCTFail("expected .transfer, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.logo, Chain.solana.logo)
        XCTAssertFalse(coin.logo.hasPrefix("http"), "native SOL should use the local bundle asset")
    }

    func test_parseSolana_transfer_returnsNil_whenOutMissing() {
        let diff = diff(
            asset: token(symbol: "USDC", address: "mint", decimals: 6),
            out: nil
        )
        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response(with: [diff])))
    }

    /// Unknown mints without Blockaid-provided decimals can't be rendered
    /// reliably — the hero needs decimals to convert raw → display, so skip.
    func test_parseSolana_transfer_returnsNil_whenDecimalsMissingAndMintUnknown() {
        let diff = diff(
            asset: BlockaidSolanaSimulationJson.Asset(
                type: "TOKEN",
                name: nil,
                symbol: "XYZ",
                address: "UnknownMintThatWillNotBeInTokensStore1111111",
                decimals: nil,
                logo: nil
            ),
            out: balance("100")
        )
        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response(with: [diff])))
    }

    // MARK: - Swap

    func test_parseSolana_swap_returnsSwapInfo() {
        let usdc = token(symbol: "USDC", address: "Usdc1111", decimals: 6)
        let bonk = token(symbol: "BONK", address: "Bonk1111", decimals: 5)
        let outDiff = diff(asset: usdc, out: balance("1000000"))
        let inDiff = diff(asset: bonk, in: balance("5000000000"))

        let info = BlockaidSimulationParser.parseSolana(response: response(with: [outDiff, inDiff]))

        guard case let .swap(fromCoin, toCoin, fromAmount, toAmount) = info else {
            return XCTFail("expected .swap, got \(String(describing: info))")
        }
        XCTAssertEqual(fromCoin.ticker, "USDC")
        XCTAssertEqual(toCoin.ticker, "BONK")
        XCTAssertEqual(fromAmount, BigInt("1000000"))
        XCTAssertEqual(toAmount, BigInt("5000000000"))
    }

    /// When Blockaid returns three diffs and one is native SOL, the parser
    /// filters the SOL diff (treated as tx fee) and parses the remaining two as
    /// a swap. Regression guard for parity with `parseBlockaidSolanaSimulation`.
    func test_parseSolana_swap_withNativeSolFee_filtersSolDiff() {
        let usdc = token(symbol: "USDC", address: "Usdc1111", decimals: 6)
        let bonk = token(symbol: "BONK", address: "Bonk1111", decimals: 5)
        let sol = native(symbol: "SOL", decimals: 9)

        let diffs = [
            diff(asset: usdc, out: balance("1000000")),
            diff(asset: sol, out: balance("5000")), // fee leg
            diff(asset: bonk, in: balance("5000000000"))
        ]
        let info = BlockaidSimulationParser.parseSolana(response: response(with: diffs))

        guard case let .swap(fromCoin, toCoin, _, _) = info else {
            return XCTFail("expected .swap after SOL-fee filter, got \(String(describing: info))")
        }
        XCTAssertEqual(fromCoin.ticker, "USDC")
        XCTAssertEqual(toCoin.ticker, "BONK")
    }

    /// A genuine swap out of native SOL must survive the same-mint netting:
    /// native SOL carries the wrapped-SOL mint sentinel, so the guard has to
    /// compare against the *other* leg's mint rather than treat every native
    /// SOL leg as wrap noise.
    func test_parseSolana_swap_nativeSolToUsdc_staysSwap() {
        let sol = native(symbol: "SOL", decimals: 9)
        let usdc = token(symbol: "USDC", address: "Usdc1111", decimals: 6)
        let diffs = [
            diff(asset: sol, out: balance("1000000000")),
            diff(asset: usdc, in: balance("150000000"))
        ]

        let info = BlockaidSimulationParser.parseSolana(response: response(with: diffs))

        guard case let .swap(fromCoin, toCoin, fromAmount, toAmount) = info else {
            return XCTFail("expected .swap, got \(String(describing: info))")
        }
        XCTAssertEqual(fromCoin.ticker, "SOL")
        XCTAssertEqual(toCoin.ticker, "USDC")
        XCTAssertEqual(fromAmount, BigInt("1000000000"))
        XCTAssertEqual(toAmount, BigInt("150000000"))
    }

    // MARK: - Same-mint netting

    /// A Kamino wrapped-SOL vault deposit wraps SOL and spends it in the same
    /// transaction, so the wSOL account is left holding only its rent-exempt
    /// residual — 2,039,280 lamports, the rent of a 165-byte token account.
    /// Blockaid reports that residual as a small incoming WSOL diff beside the
    /// real native-SOL out leg. Both legs resolve to the wrapped-SOL mint, so
    /// there is no swap here: the hero must state the net outflow, and name it
    /// SOL rather than the WSOL the user is not receiving.
    ///
    /// Raw values captured from a real Blockaid response for an Allez SOL
    /// deposit.
    func test_parseSolana_solOutWsolIn_netsToTransfer() {
        let diffs = [
            diff(asset: native(symbol: "SOL", decimals: 9), out: balance("59435000")),
            diff(
                asset: token(symbol: "WSOL", address: BlockaidSimulationParser.wrappedSolMint, decimals: 9),
                in: balance("2039280")
            )
        ]

        let info = BlockaidSimulationParser.parseSolana(response: response(with: diffs))

        guard case let .transfer(coin, amount) = info else {
            return XCTFail("expected netted .transfer, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.ticker, "SOL", "the net follows the native leg, so the ticker must not read WSOL")
        XCTAssertEqual(coin.logo, Chain.solana.logo)
        XCTAssertEqual(amount, BigInt("57395720"), "59435000 out - 2039280 in")
    }

    /// The mirror image, and the reason the pair is netted rather than reduced
    /// to its out leg: a wrapped-SOL withdraw closes the payout account, which
    /// unwraps wSOL into native SOL. The out leg is only the residual going
    /// back; the in leg is what the user actually receives. Keeping the out leg
    /// would headline 0.00203928 and drop the 0.059435 arriving — and reporting
    /// it as a transfer would state an outflow for an inflow.
    func test_parseSolana_wsolOutSolIn_netsToReceive() {
        let diffs = [
            diff(
                asset: token(symbol: "WSOL", address: BlockaidSimulationParser.wrappedSolMint, decimals: 9),
                out: balance("2039280")
            ),
            diff(asset: native(symbol: "SOL", decimals: 9), in: balance("61474280"))
        ]

        let info = BlockaidSimulationParser.parseSolana(response: response(with: diffs))

        guard case let .receive(coin, amount) = info else {
            return XCTFail("expected netted .receive, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.ticker, "SOL")
        XCTAssertEqual(coin.logo, Chain.solana.logo)
        XCTAssertEqual(amount, BigInt("59435000"), "61474280 in - 2039280 out")
    }

    /// Diff order is not contractual. The same withdraw with its legs the other
    /// way round must still net to the same inflow.
    func test_parseSolana_wsolOutSolIn_netsToReceive_regardlessOfDiffOrder() {
        let diffs = [
            diff(asset: native(symbol: "SOL", decimals: 9), in: balance("61474280")),
            diff(
                asset: token(symbol: "WSOL", address: BlockaidSimulationParser.wrappedSolMint, decimals: 9),
                out: balance("2039280")
            )
        ]

        let info = BlockaidSimulationParser.parseSolana(response: response(with: diffs))

        guard case let .receive(coin, amount) = info else {
            return XCTFail("expected netted .receive, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.ticker, "SOL")
        XCTAssertEqual(amount, BigInt("59435000"))
    }

    /// An exact wrap/unwrap round trip nets to zero. "Your balance does not
    /// change" has no honest hero, so the parser returns nil and the caller
    /// falls back to the generic title rather than headlining a zero amount.
    func test_parseSolana_sameMintExactCancellation_returnsNil() {
        let diffs = [
            diff(asset: native(symbol: "SOL", decimals: 9), out: balance("2039280")),
            diff(
                asset: token(symbol: "WSOL", address: BlockaidSimulationParser.wrappedSolMint, decimals: 9),
                in: balance("2039280")
            )
        ]

        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response(with: diffs)))
    }

    /// The three-diff native-SOL fee filter runs first, so a same-mint pair can
    /// still be what is left afterwards — here two wSOL accounts either side of
    /// a separate native-SOL fee leg. The netting must apply to the survivors.
    func test_parseSolana_threeDiffs_afterSolFeeFilter_netsSameMintPair() {
        let wsol = token(symbol: "WSOL", address: BlockaidSimulationParser.wrappedSolMint, decimals: 9)
        let diffs = [
            diff(asset: wsol, out: balance("5000000")),
            diff(asset: native(symbol: "SOL", decimals: 9), out: balance("5000")), // fee leg
            diff(asset: wsol, in: balance("1000000"))
        ]

        let info = BlockaidSimulationParser.parseSolana(response: response(with: diffs))

        guard case let .transfer(coin, amount) = info else {
            return XCTFail("expected netted .transfer, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.ticker, "WSOL")
        XCTAssertEqual(amount, BigInt("4000000"), "5000000 out - 1000000 in")
    }

    /// `raw_value` decodes a signed integer even though Blockaid states each
    /// side's magnitude and puts the direction in the field name. A negative
    /// reaching the subtraction would flip the direction of an approval
    /// headline — here it would turn a net outflow into a "Receive" — so the
    /// netting fails closed instead.
    func test_parseSolana_sameMint_negativeRawValue_returnsNil() {
        let diffs = [
            diff(asset: native(symbol: "SOL", decimals: 9), out: balance("-10")),
            diff(
                asset: token(symbol: "WSOL", address: BlockaidSimulationParser.wrappedSolMint, decimals: 9),
                in: balance("-5")
            )
        ]

        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response(with: diffs)))
    }

    /// Both sides collapse onto the first diff when the second carries no in
    /// leg. Netting a diff against itself is still that asset's net movement,
    /// so it is allowed while the skipped diff holds nothing.
    func test_parseSolana_sameMint_collapsedSources_netsWhenOtherDiffIsEmpty() {
        let wsol = token(symbol: "WSOL", address: BlockaidSimulationParser.wrappedSolMint, decimals: 9)
        let diffs = [
            diff(asset: wsol, in: balance("2000000"), out: balance("5000000")),
            diff(asset: token(symbol: "USDC", address: "Usdc1111", decimals: 6), in: nil, out: nil)
        ]

        let info = BlockaidSimulationParser.parseSolana(response: response(with: diffs))

        guard case let .transfer(coin, amount) = info else {
            return XCTFail("expected netted .transfer, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.ticker, "WSOL")
        XCTAssertEqual(amount, BigInt("3000000"), "5000000 out - 2000000 in")
    }

    /// The same collapse, but the skipped diff spends a second asset. Netting
    /// here would headline an authoritative inflow while never looking at the
    /// USDC leaving, so the parser declines and the caller falls back to the
    /// generic title.
    func test_parseSolana_sameMint_collapsedSources_returnsNil_whenOtherDiffCarriesBalance() {
        let wsol = token(symbol: "WSOL", address: BlockaidSimulationParser.wrappedSolMint, decimals: 9)
        let diffs = [
            diff(asset: wsol, in: balance("61474280"), out: balance("2039280")),
            diff(asset: token(symbol: "USDC", address: "Usdc1111", decimals: 6), out: balance("100000000"))
        ]

        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response(with: diffs)))
    }

    /// If only one side of a two-diff swap has a value, fall back to .transfer
    /// — matches the extension's `else if (outAsset && outValue)` branch.
    func test_parseSolana_swap_fallsBackToTransfer_whenInMissing() {
        let usdc = token(symbol: "USDC", address: "Usdc1111", decimals: 6)
        let bonk = token(symbol: "BONK", address: "Bonk1111", decimals: 5)
        let outDiff = diff(asset: usdc, out: balance("1000000"))
        let inDiff = diff(asset: bonk, in: nil, out: nil)

        let info = BlockaidSimulationParser.parseSolana(response: response(with: [outDiff, inDiff]))

        guard case let .transfer(coin, amount) = info else {
            return XCTFail("expected .transfer fallback, got \(String(describing: info))")
        }
        XCTAssertEqual(coin.ticker, "USDC")
        XCTAssertEqual(amount, BigInt("1000000"))
    }
}

// MARK: - Fixture helpers

private extension BlockaidSolanaSimulationParserTests {
    func response(
        with diffs: [BlockaidSolanaSimulationJson.AccountAssetDiff]
    ) -> BlockaidSolanaSimulationResponseJson {
        BlockaidSolanaSimulationResponseJson(
            result: BlockaidSolanaSimulationResponseJson.BlockaidSolanaSimulationResultJson(
                simulation: BlockaidSolanaSimulationJson(
                    accountSummary: BlockaidSolanaSimulationJson.AccountSummary(accountAssetsDiff: diffs)
                ),
                validation: nil
            ),
            status: "Success",
            error: nil
        )
    }

    func diff(
        asset: BlockaidSolanaSimulationJson.Asset,
        in inBalance: BlockaidSolanaSimulationJson.BalanceChange? = nil,
        out: BlockaidSolanaSimulationJson.BalanceChange? = nil
    ) -> BlockaidSolanaSimulationJson.AccountAssetDiff {
        BlockaidSolanaSimulationJson.AccountAssetDiff(
            asset: asset,
            assetType: asset.type,
            in: inBalance,
            out: out
        )
    }

    func token(
        symbol: String?,
        address: String,
        decimals: Int
    ) -> BlockaidSolanaSimulationJson.Asset {
        BlockaidSolanaSimulationJson.Asset(
            type: "TOKEN",
            name: nil,
            symbol: symbol,
            address: address,
            decimals: decimals,
            logo: nil
        )
    }

    func native(symbol: String, decimals: Int) -> BlockaidSolanaSimulationJson.Asset {
        BlockaidSolanaSimulationJson.Asset(
            type: "SOL",
            name: "Solana",
            symbol: symbol,
            address: nil,
            decimals: decimals,
            logo: nil
        )
    }

    func balance(_ raw: String) -> BlockaidSolanaSimulationJson.BalanceChange {
        BlockaidSolanaSimulationJson.BalanceChange(rawValue: raw)
    }
}
