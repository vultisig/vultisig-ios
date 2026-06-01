import XCTest
import BigInt
@testable import VultisigApp

/// Covers the quote-ranking logic that picks the highest net-output swap quote across the
/// eligible providers (THORChain, Maya, 1inch, KyberSwap, LI.FI). The selector replaces the
/// older priority-ordered behaviour that returned the first successful quote regardless of
/// output, which on same-chain Ethereum routes (e.g. USDC→ETH) produced very poor outcomes
/// because THORChain — listed first in the priority order for ETH/USDC — was always picked
/// even when an aggregator gave materially more destination amount for the same input.
final class SwapQuoteRankingTests: XCTestCase {

    // MARK: - expectedNetToAmount

    func test_expectedNetToAmount_thorchain_dividesByThorswapMultiplier() {
        // expectedAmountOut is in 1e8-base units (THORChain convention).
        // 3_000_000 ÷ 1e8 = 0.03 ETH.
        let quote: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "3000000"))

        XCTAssertEqual(quote.expectedNetToAmount(toCoin: ethCoin()), Decimal(string: "0.03"))
    }

    func test_expectedNetToAmount_mayachain_usesNativeDecimalsMultiplier() {
        // Maya uses pow(10, decimals) for the multiplier instead of fixed 1e8.
        // CACAO has 10 decimals → multiplier = 1e10 → 5_000_000_000 ÷ 1e10 = 0.5.
        let quote: SwapQuote = .mayachain(makeThorQuote(expectedAmountOut: "5000000000"))

        XCTAssertEqual(quote.expectedNetToAmount(toCoin: cacaoCoin()), Decimal(string: "0.5"))
    }

    func test_expectedNetToAmount_oneInch_usesDstAmountInToCoinDecimals() {
        // 1inch returns dstAmount in raw toCoin units (wei for ETH).
        let quote: SwapQuote = .oneinch(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil)

        XCTAssertEqual(quote.expectedNetToAmount(toCoin: ethCoin()), Decimal(string: "0.03"))
    }

    func test_expectedNetToAmount_kyberswap_usesDstAmountInToCoinDecimals() {
        let quote: SwapQuote = .kyberswap(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil)

        XCTAssertEqual(quote.expectedNetToAmount(toCoin: ethCoin()), Decimal(string: "0.03"))
    }

    func test_expectedNetToAmount_lifi_subtractsIntegratorFeeFromOutput() {
        // 0.03 ETH × (1 - 0.005) = 0.02985 ETH.
        let quote: SwapQuote = .lifi(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil, integratorFee: Decimal(string: "0.005"))

        XCTAssertEqual(quote.expectedNetToAmount(toCoin: ethCoin()), Decimal(string: "0.02985"))
    }

    func test_expectedNetToAmount_lifi_nilIntegratorFee_returnsRawOutput() {
        let quote: SwapQuote = .lifi(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil, integratorFee: nil)

        XCTAssertEqual(quote.expectedNetToAmount(toCoin: ethCoin()), Decimal(string: "0.03"))
    }

    func test_expectedNetToAmount_zeroOrUnparseable_returnsNil() {
        let zeroThor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "0"))
        let badThor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "abc"))
        let badEvm: SwapQuote = .oneinch(makeEVMQuote(dstAmount: ""), fee: nil)

        XCTAssertNil(zeroThor.expectedNetToAmount(toCoin: ethCoin()))
        XCTAssertNil(badThor.expectedNetToAmount(toCoin: ethCoin()))
        XCTAssertNil(badEvm.expectedNetToAmount(toCoin: ethCoin()))
    }

    // MARK: - selectBestQuote

    func test_selectBestQuote_empty_returnsNil() {
        XCTAssertNil(SwapService.selectBestQuote(quotes: [], toCoin: ethCoin()))
    }

    func test_selectBestQuote_singleRankableQuote_returnsIt() {
        let quote: SwapQuote = .oneinch(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil)

        let pick = SwapService.selectBestQuote(quotes: [quote], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, quote.displayName)
    }

    func test_selectBestQuote_singleUnrankableQuote_returnsItViaPriorityFallback() {
        let quote: SwapQuote = .oneinch(makeEVMQuote(dstAmount: ""), fee: nil)

        let pick = SwapService.selectBestQuote(quotes: [quote], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, quote.displayName)
    }

    func test_selectBestQuote_picksMaxNetOutput() {
        // THORChain comes first in the eligible-provider order for ETH/USDC, so the previous
        // first-success-wins behaviour would have returned it. The new ranking must compare
        // destination amounts and prefer the aggregator with the higher dstAmount.
        let thor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "290000")) // 0.0029 ETH
        let oneInch: SwapQuote = .oneinch(makeEVMQuote(dstAmount: "3000000000000000"), fee: nil) // 0.0030 ETH
        let lifi: SwapQuote = .lifi(makeEVMQuote(dstAmount: "2900000000000000"), fee: nil, integratorFee: nil)

        let pick = SwapService.selectBestQuote(quotes: [thor, oneInch, lifi], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "1Inch")
    }

    func test_selectBestQuote_thorchainWinsWhenItHasHighestOutput() {
        // Cross-chain or pool-aligned cases where THORChain genuinely outperforms aggregators.
        let thor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "5000000")) // 0.05 ETH
        let oneInch: SwapQuote = .oneinch(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil) // 0.03 ETH

        let pick = SwapService.selectBestQuote(quotes: [thor, oneInch], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "THORChain")
    }

    func test_selectBestQuote_allUnrankable_returnsFirstByPriority() {
        let thor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "abc"))
        let oneInch: SwapQuote = .oneinch(makeEVMQuote(dstAmount: ""), fee: nil)

        let pick = SwapService.selectBestQuote(quotes: [thor, oneInch], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "THORChain")
    }

    func test_selectBestQuote_mixedRankability_picksFromRankableOnly() {
        // Two unparseable + one good: ranking should pick the only rankable one.
        let bad1: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "abc"))
        let bad2: SwapQuote = .oneinch(makeEVMQuote(dstAmount: ""), fee: nil)
        let good: SwapQuote = .lifi(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil, integratorFee: nil)

        let pick = SwapService.selectBestQuote(quotes: [bad1, bad2, good], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "LI.FI")
    }

    // MARK: - Banded provider preference

    func test_selectBestQuote_nearTieWithinBand_priorityWins_swapKitOverLifi() {
        // SwapKit (priority 2) and LI.FI (priority 5) within 1% of each other on net output:
        // LI.FI's raw output is slightly higher but still inside the band, so the
        // higher-priority SwapKit quote wins instead of the raw maximum.
        // SwapKit reports expectedBuyAmount in human units; LI.FI 0.03 ETH dstAmount in wei.
        let swapKit: SwapQuote = .swapkit(makeSwapKitResponse(expectedBuyAmount: "0.0299"), fee: nil, subProvider: "Chainflip")
        let lifi: SwapQuote = .lifi(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil, integratorFee: nil) // 0.03

        // best = LI.FI 0.03, floor = 0.0297, SwapKit 0.0299 is in band → SwapKit wins on priority.
        let pick = SwapService.selectBestQuote(quotes: [lifi, swapKit], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "SwapKit (Chainflip)")
    }

    func test_selectBestQuote_priorityOrderingWithinBand_thorchainOverOneInch() {
        // THORChain (priority 0) vs 1inch (priority 4) within 1%: 1inch's raw output is
        // marginally higher but in band, so THORChain wins on priority.
        let thor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "2990000")) // 0.0299 ETH
        let oneInch: SwapQuote = .oneinch(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil) // 0.03 ETH

        // best = 1inch 0.03, floor = 0.0297, THORChain 0.0299 in band → THORChain wins.
        let pick = SwapService.selectBestQuote(quotes: [oneInch, thor], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "THORChain")
    }

    func test_selectBestQuote_exactBandBoundaryIsInclusive() {
        // A quote exactly at best * 0.99 is included (>= floor) and, being higher priority,
        // wins. best = 1inch 0.03 → floor = 0.0297. THORChain at exactly 0.0297 is in band.
        let thor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "2970000")) // 0.0297 ETH
        let oneInch: SwapQuote = .oneinch(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil) // 0.03 ETH

        let pick = SwapService.selectBestQuote(quotes: [oneInch, thor], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "THORChain")
    }

    func test_selectBestQuote_justOutsideBand_betterRateWins() {
        // THORChain just below the floor (best 0.03 → floor 0.0297; THORChain 0.0296) must
        // NOT win on priority — only 1inch is in band, so the better rate wins.
        let thor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "2960000")) // 0.0296 ETH
        let oneInch: SwapQuote = .oneinch(makeEVMQuote(dstAmount: "30000000000000000"), fee: nil) // 0.03 ETH

        let pick = SwapService.selectBestQuote(quotes: [oneInch, thor], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "1Inch")
    }

    // MARK: - Same-chain ERC20→ETH regression

    func test_sameChainErc20ToEth_aggregatorWinsOverThorchain() {
        // Reproduces the user-reported case that motivated this ranker: a small same-chain
        // USDC→ETH swap on Ethereum where THORChain is eligible (and listed first in the
        // priority order) but routes through its Router with a costly `depositWithExpiry`
        // deposit. An aggregator gives more destination ETH for the same input, so it must
        // win the comparison even though it appears later in the eligibility list.
        //
        // Numbers approximate a $10 swap: each provider returns ~0.003 ETH of output, with
        // 1inch slightly ahead. The fix must not regress to picking THORChain just because
        // it is the first successful quote.
        let thor: SwapQuote = .thorchain(makeThorQuote(expectedAmountOut: "290000"))
        let oneInch: SwapQuote = .oneinch(makeEVMQuote(dstAmount: "3000000000000000"), fee: nil)
        let lifi: SwapQuote = .lifi(makeEVMQuote(dstAmount: "2950000000000000"), fee: nil, integratorFee: nil)
        let kyber: SwapQuote = .kyberswap(makeEVMQuote(dstAmount: "2960000000000000"), fee: nil)

        let pick = SwapService.selectBestQuote(quotes: [thor, oneInch, lifi, kyber], toCoin: ethCoin())

        XCTAssertEqual(pick?.displayName, "1Inch")
    }

    // MARK: - Helpers

    private func ethCoin() -> Coin {
        let meta = CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: "test", hexPublicKey: "test")
    }

    private func cacaoCoin() -> Coin {
        let meta = CoinMeta(
            chain: .mayaChain,
            ticker: "CACAO",
            logo: "cacao",
            decimals: 10,
            priceProviderId: "maya-protocol",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: "test", hexPublicKey: "test")
    }

    private func makeThorQuote(expectedAmountOut: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(
                affiliate: "0",
                asset: "ETH.ETH",
                outbound: "0",
                total: "0",
                liquidity: nil,
                slippageBps: nil,
                totalBps: nil
            ),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "=:ETH.ETH:addr",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }

    /// SwapKit responses are `Decodable`-only (custom `init(from:)`, no memberwise init), so
    /// build the fixture from a minimal EVM-txType JSON payload. `expectedBuyAmount` is the
    /// field `expectedNetToAmount` reads, in human units.
    private func makeSwapKitResponse(expectedBuyAmount: String) -> SwapKitSwapResponse {
        let json = """
        {
          "swapId": "swap-1",
          "routeId": "route-1",
          "providers": ["Chainflip"],
          "sellAsset": "ETH.USDC",
          "buyAsset": "ETH.ETH",
          "sellAmount": "10",
          "expectedBuyAmount": "\(expectedBuyAmount)",
          "expectedBuyAmountMaxSlippage": "\(expectedBuyAmount)",
          "sourceAddress": "0xfrom",
          "destinationAddress": "0xto",
          "targetAddress": "0xtarget",
          "meta": { "txType": "EVM" },
          "tx": {
            "from": "0xfrom",
            "to": "0xto",
            "value": "0",
            "data": "0x",
            "gas": "200000",
            "gasPrice": "20000000000"
          },
          "fees": []
        }
        """
        // Test fixture: a decode failure here is a test bug, so force-unwrap is acceptable.
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
    }

    private func makeEVMQuote(dstAmount: String, gas: Int64 = 200_000, gasPrice: String = "20000000000") -> EVMQuote {
        EVMQuote(
            dstAmount: dstAmount,
            tx: EVMQuote.Transaction(
                from: "0xfrom",
                to: "0xto",
                data: "0x",
                value: "0",
                gasPrice: gasPrice,
                gas: gas
            )
        )
    }
}
