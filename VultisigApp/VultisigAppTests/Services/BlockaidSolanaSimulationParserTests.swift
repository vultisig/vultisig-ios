//
//  BlockaidSolanaSimulationParserTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

final class BlockaidSolanaSimulationParserTests: XCTestCase {

    // MARK: - Short-circuit paths

    func test_parseSolana_returnsNil_whenResultMissing() {
        let response = BlockaidSolanaSimulationResponseJson(result: nil, status: "Success", error: nil)
        XCTAssertNil(BlockaidSimulationParser.parseSolana(response: response))
    }

    func test_parseSolana_returnsNil_whenSimulationMissing() {
        let response = BlockaidSolanaSimulationResponseJson(
            result: BlockaidSolanaSimulationResponseJson.BlockaidSolanaSimulationResultJson(simulation: nil),
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
                )
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
