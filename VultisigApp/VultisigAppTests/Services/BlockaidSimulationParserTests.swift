//
//  BlockaidSimulationParserTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

final class BlockaidSimulationParserTests: XCTestCase {

    // MARK: - Short-circuit paths

    func test_parse_returnsNil_whenSimulationMissing() {
        let response = BlockaidEvmSimulationResponseJson(simulation: nil, validation: nil, error: nil)
        XCTAssertNil(BlockaidSimulationParser.parse(response: response, chain: .ethereum))
    }

    func test_parse_returnsNil_whenAssetsDiffsNil() {
        let response = response(with: [])
        XCTAssertNil(BlockaidSimulationParser.parse(response: response, chain: .ethereum))
    }

    func test_parse_returnsNil_whenAssetsDiffsEmpty() {
        let response = response(with: [])
        XCTAssertNil(BlockaidSimulationParser.parse(response: response, chain: .ethereum))
    }

    // MARK: - Transfer

    func test_parse_transfer_returnsTransferInfo() {
        let diff = diff(
            asset: asset(symbol: "USDC", decimals: 6, address: "0xUsdc", logo: "https://usdc.png"),
            out: [balance("1500000")]
        )
        let result = BlockaidSimulationParser.parse(response: response(with: [diff]), chain: .ethereum)

        guard case let .transfer(coin, amount) = result else {
            return XCTFail("expected .transfer, got \(String(describing: result))")
        }
        XCTAssertEqual(coin.ticker, "USDC")
        XCTAssertEqual(coin.decimals, 6)
        XCTAssertEqual(coin.address, "0xUsdc")
        XCTAssertEqual(coin.logo, "https://usdc.png")
        XCTAssertEqual(amount, BigInt("1500000"))
    }

    func test_parse_transfer_returnsNil_whenOutEmpty() {
        let diff = diff(
            asset: asset(symbol: "USDC", decimals: 6),
            out: nil
        )
        XCTAssertNil(BlockaidSimulationParser.parse(response: response(with: [diff]), chain: .ethereum))
    }

    func test_parse_transfer_returnsNil_whenAssetMissingSymbol() {
        let diff = diff(
            asset: asset(symbol: nil, decimals: 6),
            out: [balance("100")]
        )
        XCTAssertNil(BlockaidSimulationParser.parse(response: response(with: [diff]), chain: .ethereum))
    }

    func test_parse_transfer_returnsNil_whenAssetMissingDecimals() {
        let diff = diff(
            asset: asset(symbol: "USDC", decimals: nil),
            out: [balance("100")]
        )
        XCTAssertNil(BlockaidSimulationParser.parse(response: response(with: [diff]), chain: .ethereum))
    }

    // MARK: - Swap

    func test_parse_swap_returnsSwapInfo() {
        let outDiff = diff(
            asset: asset(symbol: "USDC", decimals: 6, address: "0xUsdc"),
            out: [balance("1000000")]
        )
        let inDiff = diff(
            asset: asset(symbol: "WETH", decimals: 18, address: "0xWeth"),
            in: [balance("300000000000000000")]
        )
        let result = BlockaidSimulationParser.parse(response: response(with: [outDiff, inDiff]), chain: .ethereum)

        guard case let .swap(fromCoin, toCoin, fromAmount, toAmount) = result else {
            return XCTFail("expected .swap, got \(String(describing: result))")
        }
        XCTAssertEqual(fromCoin.ticker, "USDC")
        XCTAssertEqual(toCoin.ticker, "WETH")
        XCTAssertEqual(fromAmount, BigInt("1000000"))
        XCTAssertEqual(toAmount, BigInt("300000000000000000"))
    }

    /// Blockaid encodes `raw_value` as hex with `0x` prefix — `BigInt(String)`
    /// with default base 10 would silently drop these. Regression guard against
    /// the parser returning nil on a valid response (WETH → ETH unwrap).
    func test_parse_swap_acceptsHexRawValues() {
        let outDiff = diff(
            asset: asset(symbol: "WETH", decimals: 18, address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", type: "ERC20"),
            out: [balance("0x75652c52418a6")]
        )
        let inDiff = diff(
            asset: asset(symbol: "ETH", decimals: 18, address: nil, type: "NATIVE"),
            in: [balance("0x75652c52418a6")]
        )
        let result = BlockaidSimulationParser.parse(response: response(with: [inDiff, outDiff]), chain: .ethereum)

        guard case let .swap(fromCoin, toCoin, fromAmount, toAmount) = result else {
            return XCTFail("expected .swap, got \(String(describing: result))")
        }
        XCTAssertEqual(fromCoin.ticker, "WETH")
        XCTAssertEqual(toCoin.ticker, "ETH")
        let expected = BigInt("75652c52418a6", radix: 16)
        XCTAssertEqual(fromAmount, expected)
        XCTAssertEqual(toAmount, expected)
    }

    func test_parse_transfer_acceptsHexRawValue() {
        let diff = diff(
            asset: asset(symbol: "USDC", decimals: 6, address: "0xUsdc"),
            out: [balance("0xF4240")] // 1_000_000
        )
        let result = BlockaidSimulationParser.parse(response: response(with: [diff]), chain: .ethereum)

        guard case let .transfer(_, amount) = result else {
            return XCTFail("expected .transfer, got \(String(describing: result))")
        }
        XCTAssertEqual(amount, BigInt("1000000"))
    }

    // MARK: - Decimal + formatting

    func test_fromAmountDecimal_usesCoinDecimals() {
        let usdc = BlockaidSimulationInfo.transfer(
            fromCoin: BlockaidSimulationCoin(chain: .ethereum, address: nil, ticker: "USDC", logo: "", decimals: 6),
            fromAmount: BigInt("1500000")
        )
        XCTAssertEqual(usdc.fromAmountDecimal, Decimal(string: "1.5"))

        let weth = BlockaidSimulationInfo.transfer(
            fromCoin: BlockaidSimulationCoin(chain: .ethereum, address: nil, ticker: "WETH", logo: "", decimals: 18),
            fromAmount: BigInt("2500000000000000000")
        )
        XCTAssertEqual(weth.fromAmountDecimal, Decimal(string: "2.5"))
    }

    func test_heroAmountText_matchesFormatForDisplay() {
        let twoFive = BlockaidSimulationInfo.transfer(
            fromCoin: BlockaidSimulationCoin(chain: .ethereum, address: nil, ticker: "WETH", logo: "", decimals: 18),
            fromAmount: BigInt("2500000000000000000")
        )
        XCTAssertEqual(twoFive.heroAmountText, Decimal(string: "2.5")!.formatForDisplay())

        let whole = BlockaidSimulationInfo.transfer(
            fromCoin: BlockaidSimulationCoin(chain: .ethereum, address: nil, ticker: "USDC", logo: "", decimals: 6),
            fromAmount: BigInt("42000000")
        )
        XCTAssertEqual(whole.heroAmountText, Decimal(string: "42")!.formatForDisplay())
    }

    // MARK: - Swap-side accessors

    func test_transferInfo_toSideAccessors_areNil() {
        let info = BlockaidSimulationInfo.transfer(
            fromCoin: simulationCoin(ticker: "USDC", decimals: 6),
            fromAmount: BigInt("1500000")
        )
        XCTAssertNil(info.toCoin)
        XCTAssertNil(info.toAmount)
        XCTAssertNil(info.toAmountDecimal)
        XCTAssertNil(info.heroToAmountText)
    }

    func test_swapInfo_toSideAccessors_exposeToSide() {
        let info = BlockaidSimulationInfo.swap(
            fromCoin: simulationCoin(ticker: "ETH", decimals: 18),
            toCoin: simulationCoin(ticker: "USDC", decimals: 6),
            fromAmount: BigInt("1000000000000000000"), // 1 ETH
            toAmount: BigInt("3000000000")             // 3000 USDC
        )
        XCTAssertEqual(info.toCoin?.ticker, "USDC")
        XCTAssertEqual(info.toAmount, BigInt("3000000000"))
        XCTAssertEqual(info.toAmountDecimal, Decimal(3000))
        XCTAssertEqual(info.heroToAmountText, Decimal(3000).formatForDisplay())
    }
}

// MARK: - Fixture helpers

private extension BlockaidSimulationParserTests {
    func response(
        with diffs: [BlockaidEvmSimulationJson.AssetDiff]
    ) -> BlockaidEvmSimulationResponseJson {
        BlockaidEvmSimulationResponseJson(
            simulation: BlockaidEvmSimulationJson(
                status: "Success",
                accountSummary: BlockaidEvmSimulationJson.AccountSummary(assetsDiffs: diffs)
            ),
            validation: nil,
            error: nil
        )
    }

    func diff(
        asset: BlockaidEvmSimulationJson.Asset,
        in inBalances: [BlockaidEvmSimulationJson.BalanceChange]? = nil,
        out: [BlockaidEvmSimulationJson.BalanceChange]? = nil
    ) -> BlockaidEvmSimulationJson.AssetDiff {
        BlockaidEvmSimulationJson.AssetDiff(
            asset: asset,
            assetType: asset.type,
            in: inBalances,
            out: out
        )
    }

    func asset(
        symbol: String?,
        decimals: Int?,
        address: String? = nil,
        logo: String? = nil,
        type: String = "ERC20"
    ) -> BlockaidEvmSimulationJson.Asset {
        BlockaidEvmSimulationJson.Asset(
            type: type,
            decimals: decimals,
            address: address,
            logoUrl: logo,
            name: nil,
            symbol: symbol
        )
    }

    func balance(_ raw: String) -> BlockaidEvmSimulationJson.BalanceChange {
        BlockaidEvmSimulationJson.BalanceChange(rawValue: raw)
    }

    func simulationCoin(ticker: String, decimals: Int) -> BlockaidSimulationCoin {
        BlockaidSimulationCoin(
            chain: .ethereum,
            address: nil,
            ticker: ticker,
            logo: "",
            decimals: decimals
        )
    }
}
