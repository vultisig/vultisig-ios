//
//  SwapHighFeeRouteMarkingTests.swift
//  VultisigAppTests
//
//  Pins the "high fee" mark on Select-route rows: which routes get it, which
//  never do, and — most importantly — that it depends only on the route.
//
//  Every numeric fixture below is a real THORChain/MAYAChain response captured
//  for BTC.BTC -> ETH.ETH at 14844 sat, at both ends of the affiliate range the
//  app can send (0 bps in DEBUG, 50 bps un-discounted in Release).
//

import BigInt
import XCTest
@testable import VultisigApp

final class SwapHighFeeRouteMarkingTests: XCTestCase {

    // Live MAYAChain quote, affiliate_bps=0 -> route fee is 1502 bps of gross.
    private let mayaNoAffiliate = (out: "424259", total: "75008", affiliate: "0")
    // The same MAYAChain quote at affiliate_bps=50. The affiliate cut grew and
    // the output shrank by exactly that much; the route itself did not change.
    private let mayaWithAffiliate = (out: "421763", total: "77504", affiliate: "2496")

    // Live THORChain quote for the same swap -> 284 bps, a healthy route.
    private let thorNoAffiliate = (out: "485317", total: "14234", affiliate: "0")
    private let thorWithAffiliate = (out: "482824", total: "16727", affiliate: "2493")

    // MARK: - Above / below the threshold

    func testRouteAboveThresholdIsMarked() {
        let quote = SwapQuote.mayachain(makeQuote(mayaNoAffiliate))

        XCTAssertEqual(SwapService.routeFeeBps(for: quote), 1502)
        XCTAssertTrue(
            SwapService.isHighFeeRoute(quote),
            "A route taking 15% of the swap must be marked"
        )
    }

    func testRouteBelowThresholdIsNotMarked() {
        let quote = SwapQuote.thorchain(makeQuote(thorNoAffiliate))

        XCTAssertEqual(SwapService.routeFeeBps(for: quote), 284)
        XCTAssertFalse(
            SwapService.isHighFeeRoute(quote),
            "A 2.8% route is a normal swap and must not be marked"
        )
    }

    /// Both sides of the line, on the same pair and amount, so the test fails if
    /// the threshold ever moves far enough to reclassify real routes.
    func testThresholdSeparatesTheTwoLiveRoutesForTheSameSwap() {
        XCTAssertTrue(SwapService.isHighFeeRoute(.mayachain(makeQuote(mayaNoAffiliate))))
        XCTAssertFalse(SwapService.isHighFeeRoute(.thorchain(makeQuote(thorNoAffiliate))))
    }

    func testThresholdIsInclusiveAtItsBoundary() {
        // gross = 10_000, so the fee IS the bps figure.
        let atThreshold = SwapQuote.thorchain(makeQuote((out: "9000", total: "1000", affiliate: "0")))
        let justUnder = SwapQuote.thorchain(makeQuote((out: "9001", total: "999", affiliate: "0")))

        XCTAssertEqual(SwapService.routeFeeBps(for: atThreshold), SwapService.highRouteFeeThresholdBps)
        XCTAssertTrue(SwapService.isHighFeeRoute(atThreshold), "The boundary itself is marked")
        XCTAssertFalse(SwapService.isHighFeeRoute(justUnder), "One bps under is not")
    }

    // MARK: - Tier invariance (the reason the affiliate cut is excluded)

    /// The headline property. The affiliate bps the app sends moves with the
    /// user's VULT tier, and it sits inside `fees.total`. If the mark were driven
    /// off the node's `fees.total_bps` it would move 34-50 bps with the tier and
    /// could flip a row. With the affiliate backed out the figure is identical.
    func testAffiliateCutIsExcludedSoTheTierCannotChangeTheMark() {
        let withoutAffiliate = SwapQuote.mayachain(makeQuote(mayaNoAffiliate))
        let withAffiliate = SwapQuote.mayachain(makeQuote(mayaWithAffiliate))

        XCTAssertEqual(
            SwapService.routeFeeBps(for: withAffiliate),
            SwapService.routeFeeBps(for: withoutAffiliate),
            "The same route at two VULT tiers must measure identically"
        )
        XCTAssertEqual(SwapService.routeFeeBps(for: withAffiliate), 1502)
    }

    func testTierInvarianceAlsoHoldsForAHealthyRoute() {
        XCTAssertEqual(
            SwapService.routeFeeBps(for: .thorchain(makeQuote(thorWithAffiliate))),
            SwapService.routeFeeBps(for: .thorchain(makeQuote(thorNoAffiliate))),
            "Tier invariance is a property of the metric, not of high-fee routes"
        )
        XCTAssertFalse(SwapService.isHighFeeRoute(.thorchain(makeQuote(thorWithAffiliate))))
    }

    /// The node's own `fees.total_bps` is a different quantity from this ratio,
    /// and the gap is provider-dependent (MAYAChain reported 1306 where the fee
    /// is 1502 bps of gross). Reading the node's field would put rows in one list
    /// on two scales, so it must not influence the mark.
    func testNodeReportedTotalBpsDoesNotDriveTheMark() {
        let quote = SwapQuote.mayachain(
            makeQuote(mayaNoAffiliate, totalBps: 10)
        )

        XCTAssertEqual(SwapService.routeFeeBps(for: quote), 1502)
        XCTAssertTrue(
            SwapService.isHighFeeRoute(quote),
            "A low total_bps on the payload must not suppress the mark"
        )
    }

    // MARK: - Independence from the below-minimum filter

    /// Marking and filtering are separate mechanisms. The filter
    /// (`belowRecommendedMinimumError`) decides whether a candidate reaches the
    /// picker at all; the mark describes a candidate that already did. Neither
    /// may read the other's input.
    func testMarkingIgnoresTheRecommendedMinimum() {
        let clearsFloor = SwapQuote.mayachain(
            makeQuote(mayaNoAffiliate, recommendedMinAmountIn: "0")
        )
        let farBelowFloor = SwapQuote.mayachain(
            makeQuote(mayaNoAffiliate, recommendedMinAmountIn: "999999999")
        )

        XCTAssertEqual(
            SwapService.routeFeeBps(for: clearsFloor),
            SwapService.routeFeeBps(for: farBelowFloor),
            "The node's floor must not affect the fee measurement"
        )
        XCTAssertTrue(SwapService.isHighFeeRoute(clearsFloor))
        XCTAssertTrue(SwapService.isHighFeeRoute(farBelowFloor))
    }

    /// The converse: clearing the floor is not a clean bill of health. This is
    /// exactly the reported case — the amount clears MAYAChain's own recommended
    /// minimum and the route still charges 15%.
    func testARouteThatClearsTheFloorCanStillBeMarked() {
        let btc = makeCoin(.bitcoin, ticker: "BTC")
        let normalizedAmount = Decimal(14844)

        XCTAssertNil(
            SwapService.belowRecommendedMinimumError(
                normalizedAmount: normalizedAmount,
                recommendedMinAmountIn: "14455",
                fromCoin: btc
            ),
            "14844 clears the 14455 floor, so the candidate is not filtered out"
        )
        XCTAssertTrue(
            SwapService.isHighFeeRoute(.mayachain(makeQuote(mayaNoAffiliate))),
            "...and it is still a 15% route, so it is marked"
        )
    }

    // MARK: - Routes that cannot be measured

    /// Aggregators expose no gross-vs-net breakdown. The badge asserts a
    /// measurement, so an unmeasurable route must never carry it.
    func testAggregatorRoutesAreNeverMarked() throws {
        let swapKitResponse = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-btc-all-swap"
        )
        let aggregators: [SwapQuote] = [
            .oneinch(makeEVMQuote(), fee: nil),
            .kyberswap(makeEVMQuote(), fee: nil),
            .lifi(makeEVMQuote(), fee: nil, integratorFee: nil),
            .swapkit(swapKitResponse, fee: nil, subProvider: swapKitResponse.subProvider),
            .jupiter(makeEVMQuote(), fee: nil, platformFee: 0, feeOnInput: false)
        ]

        for quote in aggregators {
            XCTAssertNil(
                SwapService.routeFeeBps(for: quote),
                "\(quote.displayName ?? "?") exposes no fee breakdown"
            )
            XCTAssertFalse(SwapService.isHighFeeRoute(quote))
        }
    }

    func testUnparseableFeeFieldsAreNotMarked() {
        let badTotal = SwapQuote.mayachain(makeQuote((out: "424259", total: "n/a", affiliate: "0")))
        let badOut = SwapQuote.mayachain(makeQuote((out: "", total: "75008", affiliate: "0")))

        XCTAssertNil(SwapService.routeFeeBps(for: badTotal))
        XCTAssertNil(SwapService.routeFeeBps(for: badOut))
        XCTAssertFalse(SwapService.isHighFeeRoute(badTotal))
        XCTAssertFalse(SwapService.isHighFeeRoute(badOut))
    }

    /// An unreadable affiliate must not default to zero. Doing so would fold the
    /// Vultisig cut back into the figure and could mark a route on the strength
    /// of our own fee — the one number this metric exists to exclude.
    func testUnparseableAffiliateYieldsNoMeasurementRatherThanZero() {
        let quote = SwapQuote.mayachain(makeQuote((out: "424259", total: "75008", affiliate: "n/a")))

        XCTAssertNil(
            SwapService.routeFeeBps(for: quote),
            "A missing affiliate must not be silently treated as 0"
        )
        XCTAssertFalse(SwapService.isHighFeeRoute(quote))
    }

    /// Nonsense sign combinations produce no measurement rather than a plausible
    /// looking number. Each of these would otherwise yield a value in or beyond
    /// the normal bps range and could mark, or fail to mark, a row on garbage.
    func testImpossibleFeeShapesYieldNoMeasurement() {
        let shapes: [(String, (out: String, total: String, affiliate: String))] = [
            ("negative output", (out: "-100", total: "50", affiliate: "0")),
            ("negative total", (out: "100", total: "-50", affiliate: "0")),
            ("negative affiliate", (out: "1000", total: "500", affiliate: "-100")),
            ("affiliate exceeding total", (out: "1000", total: "500", affiliate: "600"))
        ]

        for (label, fees) in shapes {
            let quote = SwapQuote.mayachain(makeQuote(fees))
            XCTAssertNil(SwapService.routeFeeBps(for: quote), "\(label) must not measure")
            XCTAssertFalse(SwapService.isHighFeeRoute(quote), "\(label) must not be marked")
        }
    }

    func testZeroGrossIsNotMarked() {
        let quote = SwapQuote.mayachain(makeQuote((out: "0", total: "0", affiliate: "0")))

        XCTAssertNil(SwapService.routeFeeBps(for: quote), "A zero-value swap has no fee share")
        XCTAssertFalse(SwapService.isHighFeeRoute(quote))
    }

    /// An affiliate-only fee means the route itself charged nothing, which is a
    /// measurement of zero rather than an absent measurement.
    func testAffiliateOnlyFeeMeasuresZeroAndIsNotMarked() {
        let quote = SwapQuote.mayachain(makeQuote((out: "100000", total: "2496", affiliate: "2496")))

        XCTAssertEqual(SwapService.routeFeeBps(for: quote), 0)
        XCTAssertFalse(SwapService.isHighFeeRoute(quote))
    }

    // MARK: - Helpers

    private func makeQuote(
        _ fees: (out: String, total: String, affiliate: String),
        totalBps: Int? = nil,
        recommendedMinAmountIn: String = "0"
    ) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: fees.out,
            expiry: 0,
            fees: Fees(
                affiliate: fees.affiliate,
                asset: "ETH.ETH",
                outbound: "75000",
                total: fees.total,
                liquidity: "8",
                slippageBps: 0,
                totalBps: totalBps
            ),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "memo",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: recommendedMinAmountIn,
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }

    private func makeEVMQuote() -> EVMQuote {
        EVMQuote(
            dstAmount: "1000",
            tx: EVMQuote.Transaction(
                from: "0xfrom", to: "0xto", data: "0x", value: "0", gasPrice: "0", gas: 0
            )
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: 8, isNativeToken: true)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }
}
