//
//  SwapReworkLogicTests.swift
//  VultisigAppTests
//
//  The reworked swap form's own logic: route ranking, the fee breakdown with
//  the VULT tier, quote expiry, the price-move gate, keypad input, issue
//  resolution, the tracker stages and the unverified-token check.
//

import XCTest

@testable import VultisigApp

private func dec(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
}

final class SwapRouteRankingTests: XCTestCase {

    private func option(_ id: String, _ received: String, fees: String? = nil, eta: Int? = nil) -> SwapRouteOption {
        SwapRouteOption(
            id: id, providerName: id, providerLogo: nil,
            receivedAmount: dec(received), receivedFiat: nil,
            feesFiat: fees.map(dec), etaSeconds: eta
        )
    }

    func testRanksByReceivedAmountDescending() {
        let ranked = SwapRouteRanking.rank([
            option("Chainflip", "0.013989", eta: 390),
            option("THORChain", "0.0140218", eta: 600),
            option("LI.FI", "0.0139412")
        ])
        XCTAssertEqual(ranked.map(\.id), ["THORChain", "Chainflip", "LI.FI"])
        XCTAssertEqual(ranked.first?.tags, [.bestPrice])
        XCTAssertEqual(ranked.first?.shortfall, 0)
        XCTAssertEqual(ranked[1].shortfall, dec("0.0140218") - dec("0.013989"))
    }

    func testFastestTagGoesToAQuickerDifferentRoute() {
        let ranked = SwapRouteRanking.rank([
            option("THORChain", "0.0140218", eta: 600),
            option("Chainflip", "0.013989", eta: 390)
        ])
        XCTAssertEqual(ranked.first { $0.id == "Chainflip" }?.tags, [.fastest])
    }

    func testNoFastestTagWhenBestIsAlsoFastest() {
        let ranked = SwapRouteRanking.rank([
            option("THORChain", "0.0140218", eta: 300),
            option("Chainflip", "0.013989", eta: 390)
        ])
        XCTAssertFalse(ranked.contains { $0.tags.contains(.fastest) })
    }

    func testRouteWithoutEtaNeverWinsFastest() {
        let ranked = SwapRouteRanking.rank([
            option("1inch", "1.0"),
            option("KyberSwap", "0.99")
        ])
        XCTAssertFalse(ranked.contains { $0.tags.contains(.fastest) })
    }

    func testTieBreaksOnLowerFeeThenFasterThenName() {
        let ranked = SwapRouteRanking.rank([
            option("B", "1", fees: "2"),
            option("A", "1", fees: "2"),
            option("C", "1", fees: "1")
        ])
        XCTAssertEqual(ranked.map(\.id), ["C", "A", "B"])
    }

    func testDropsRoutesThatPayNothing() {
        XCTAssertTrue(SwapRouteRanking.rank([option("Broken", "0")]).isEmpty)
        XCTAssertEqual(SwapRouteRanking.rank([option("Broken", "0"), option("Ok", "1")]).map(\.id), ["Ok"])
    }

    func testActiveRouteKeepsPickWhileItQuotes() {
        let ranked = SwapRouteRanking.rank([option("A", "2"), option("B", "1")])
        XCTAssertEqual(SwapRouteRanking.activeRoute(in: ranked, selectedID: "B")?.id, "B")
        XCTAssertEqual(SwapRouteRanking.activeRoute(in: ranked, selectedID: "Gone")?.id, "A")
        XCTAssertEqual(SwapRouteRanking.activeRoute(in: ranked, selectedID: nil)?.id, "A")
    }
}

final class SwapFeeBreakdownTests: XCTestCase {

    private func breakdown(
        network: String = "0.84", protocolFee: String = "2.86",
        net: String = "2.93", list: String = "4.89", referral: String = "0",
        discountBps: Int = 20, tier: VultDiscountTier? = .gold,
        includedInRate: Bool = false, pay: String = "978.20", receive: String = "972.41"
    ) -> SwapFeeBreakdown {
        SwapFeeBreakdown(.init(
            networkFiat: dec(network), networkCrypto: "0.00043 ETH",
            protocolFiat: dec(protocolFee),
            vultisigNetFiat: dec(net), vultisigListFiat: dec(list),
            referralFiat: dec(referral),
            listBps: 50, tierDiscountBps: discountBps, tier: tier,
            vultisigIncludedInRate: includedInRate,
            payFiat: dec(pay), receiveFiat: dec(receive)
        ))
    }

    func testRowsAddUpToTheTotal() {
        let fees = breakdown()
        XCTAssertEqual(fees.totalFiat, dec("6.63"))
        XCTAssertEqual(fees.totalDebitFiat, dec("979.04"))
    }

    func testGoldTierRateAndSavings() {
        let fees = breakdown()
        XCTAssertEqual(fees.effectiveBps, 30)
        XCTAssertEqual(fees.effectiveRateText, "0.30%")
        XCTAssertEqual(fees.listRateText, "0.50%")
        XCTAssertEqual(fees.percentOff, 40)
        XCTAssertEqual(fees.tierSavingsFiat, dec("1.96"))
        XCTAssertTrue(fees.showsStrikethrough)
    }

    func testEveryTierMapsToTheTable() {
        let expected: [VultDiscountTier: Int] = [.bronze: 45, .silver: 40, .gold: 30, .platinum: 25, .diamond: 15, .ultimate: 0]
        for (tier, bps) in expected {
            XCTAssertEqual(breakdown(discountBps: tier.bpsDiscount, tier: tier).effectiveBps, bps, "\(tier)")
        }
        XCTAssertEqual(breakdown(discountBps: 0, tier: nil).effectiveBps, 50)
    }

    func testUltimateWaiverShowsZeroAndFullSavings() {
        let fees = breakdown(net: "0", list: "4.89", discountBps: .max, tier: .ultimate)
        XCTAssertEqual(fees.effectiveRateText, "0.00%")
        XCTAssertEqual(fees.percentOff, 100)
        XCTAssertEqual(fees.tierSavingsFiat, dec("4.89"))
        XCTAssertEqual(fees.totalFiat, dec("3.70"))
    }

    func testReferralIsNotCountedAsTierSavings() {
        let fees = breakdown(net: "2.43", list: "4.89", referral: "0.50")
        XCTAssertEqual(fees.tierSavingsFiat, dec("1.96"))
    }

    func testIncludedInRateAddsNothingAndStrikesNothing() {
        let fees = breakdown(net: "0", list: "0", includedInRate: true)
        XCTAssertEqual(fees.totalFiat, dec("3.70"))
        XCTAssertFalse(fees.showsStrikethrough)
        XCTAssertEqual(fees.tierSavingsFiat, 0)
    }

    func testZeroChargeOnTheQuoteStatesZeroRate() {
        let fees = breakdown(net: "0", list: "0", discountBps: 0, tier: nil)
        XCTAssertTrue(fees.isWaivedByQuote)
        XCTAssertEqual(fees.chargedRateText, "0.00%")
        XCTAssertEqual(breakdown().chargedRateText, "0.30%")
        XCTAssertFalse(breakdown(net: "0", list: "4.89", discountBps: .max, tier: .ultimate).isWaivedByQuote)
    }

    func testChargedRateIncludesReferralOnTopOfTier() {
        // Gold (30 bps) + 5 bps referral: the quote charges 25 bps of 50.
        let fees = breakdown(net: "2.445", list: "4.89", referral: "0.489")
        XCTAssertEqual(fees.chargedBps, 25)
        XCTAssertEqual(fees.chargedRateText, "0.25%")
        XCTAssertEqual(fees.effectiveRateText, "0.30%")
    }

    func testDisplayedRowsAddUpToDisplayedTotal() {
        let fees = breakdown(network: "0.009", protocolFee: "0.009", net: "0.009", list: "0.015")
        XCTAssertEqual(fees.displayTotalFiat, 0)
        XCTAssertEqual(breakdown().displayTotalFiat, dec("6.63"))
        XCTAssertEqual(breakdown(network: "0.849", protocolFee: "2.861", net: "2.937").displayTotalFiat, dec("6.63"))
    }

    func testAllInChangeIncludesGas() {
        // (972.41 - 979.04) / 979.04 = -0.677...%
        XCTAssertEqual(breakdown().allInChangeText, "-0.68%")
        XCTAssertEqual(breakdown(network: "0", pay: "100", receive: "101").allInChangeText, "+1.00%")
        XCTAssertNil(breakdown(receive: "0").allInChangeText)
    }
}

final class SwapQuoteClockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testIdleUntilAQuoteLands() {
        XCTAssertEqual(SwapQuoteClock().state(at: start), .idle)
    }

    func testLiveCountsDownThenRefreshesThenExpires() {
        var clock = SwapQuoteClock(lifetime: 60, grace: 15)
        clock.quoteReceived(at: start)
        XCTAssertEqual(clock.state(at: start), .live(secondsLeft: 60))
        XCTAssertEqual(clock.state(at: start.addingTimeInterval(13)), .live(secondsLeft: 47))
        XCTAssertEqual(clock.state(at: start.addingTimeInterval(59.5)), .live(secondsLeft: 1))
        XCTAssertEqual(clock.state(at: start.addingTimeInterval(60)), .refreshing)
        XCTAssertFalse(clock.isExpired(at: start.addingTimeInterval(74)))
        XCTAssertTrue(clock.isExpired(at: start.addingTimeInterval(75)))
    }

    func testNewQuoteRestartsTheClock() {
        var clock = SwapQuoteClock(lifetime: 60, grace: 15)
        clock.quoteReceived(at: start)
        clock.quoteReceived(at: start.addingTimeInterval(70))
        XCTAssertEqual(clock.state(at: start.addingTimeInterval(80)), .live(secondsLeft: 50))
        clock.reset()
        XCTAssertEqual(clock.state(at: start.addingTimeInterval(80)), .idle)
    }

    func testRemainingFractionAndText() {
        var clock = SwapQuoteClock(lifetime: 60, grace: 15)
        clock.quoteReceived(at: start)
        XCTAssertEqual(clock.remainingFraction(at: start.addingTimeInterval(30)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(clock.remainingFraction(at: start.addingTimeInterval(90)), 0)
        XCTAssertEqual(SwapQuoteClock.countdownText(seconds: 47), "0:47")
        XCTAssertEqual(SwapQuoteClock.countdownText(seconds: 0), "0:00")
        XCTAssertEqual(SwapQuoteClock.countdownText(seconds: -3), "0:00")
    }
}

final class SwapPriceMoveTests: XCTestCase {

    func testWorseBeyondThresholdNeedsConfirmation() {
        let move = SwapPriceMove.evaluate(acknowledged: dec("0.0140218"), current: dec("0.0139657"), threshold: dec("0.0025"))
        XCTAssertTrue(move.needsConfirmation)
        XCTAssertEqual(move.changeText, "0.40%")
    }

    func testSmallDropAndImprovementPassThrough() {
        XCTAssertEqual(SwapPriceMove.evaluate(acknowledged: 100, current: dec("99.9"), threshold: dec("0.0025")), .unchanged)
        XCTAssertFalse(SwapPriceMove.evaluate(acknowledged: 100, current: 101).needsConfirmation)
        XCTAssertEqual(SwapPriceMove.evaluate(acknowledged: nil, current: 1), .unchanged)
    }
}

final class SwapKeypadInputTests: XCTestCase {

    private func typed(_ keys: [PerpsKeypadKey], decimals: Int = 8) -> String {
        keys.reduce("") { SwapKeypadInput.apply($1, to: $0, maxFractionDigits: decimals) }
    }

    func testDotIsAlwaysAPeriodAndSingle() {
        XCTAssertEqual(typed([.dot]), "0.")
        XCTAssertEqual(typed([.digit(1), .dot, .dot, .digit(5)]), "1.5")
    }

    func testFractionCappedAtCoinPrecision() {
        XCTAssertEqual(typed([.digit(1), .dot, .digit(1), .digit(2), .digit(3)], decimals: 2), "1.12")
        XCTAssertEqual(typed([.digit(1), .dot], decimals: 0), "1")
    }

    func testNoLeadingZerosAndDeleteClears() {
        XCTAssertEqual(typed([.digit(0), .digit(0), .digit(7)]), "7")
        XCTAssertEqual(typed([.digit(0), .dot, .delete]), "")
        XCTAssertEqual(typed([.digit(5), .delete]), "")
    }

    func testNormalizedAndDisplay() {
        XCTAssertEqual(SwapKeypadInput.normalized(dec("1.283670000"), maxFractionDigits: 8), "1.28367")
        XCTAssertEqual(SwapKeypadInput.normalized(dec("0.123456789"), maxFractionDigits: 6), "0.123456")
        XCTAssertEqual(SwapKeypadInput.normalized(0, maxFractionDigits: 8), "")
        XCTAssertEqual(SwapKeypadInput.display("1234567.50"), "1,234,567.50")
        XCTAssertEqual(SwapKeypadInput.display("0."), "0.")
        XCTAssertEqual(SwapKeypadInput.display(""), "0")
    }
}

final class SwapReworkIssueTests: XCTestCase {

    private func context(
        balance: SwapCryptoLogic.Errors? = nil, error: Error? = nil,
        expired: Bool = false, move: SwapPriceMove = .unchanged
    ) -> SwapReworkIssue.Context {
        .init(hasAmount: true, balanceError: balance, quoteError: error, isQuoteExpired: expired, priceMove: move, nativeProviderName: "THORChain")
    }

    func testProviderErrorsMapToIssues() {
        XCTAssertEqual(SwapReworkIssue.resolve(context(error: SwapError.tradingHalted)), .tradingHalted(providerName: "THORChain"))
        XCTAssertEqual(SwapReworkIssue.resolve(context(error: SwapError.routeUnavailable)), .noRoute)
        XCTAssertEqual(SwapReworkIssue.resolve(context(error: SwapError.noLiquidityPool)), .noRoute)
        XCTAssertEqual(SwapReworkIssue.resolve(context(error: SwapError.lessThenMinSwapAmount(amount: "1"))), .amountTooSmall)
    }

    func testPriorityRouteThenExpiryThenBalanceThenPrice() {
        XCTAssertEqual(SwapReworkIssue.resolve(context(balance: .insufficientGas, error: SwapError.tradingHalted, expired: true)),
                       .tradingHalted(providerName: "THORChain"))
        XCTAssertEqual(SwapReworkIssue.resolve(context(balance: .insufficientGas, expired: true)), .quoteExpired)
        XCTAssertEqual(SwapReworkIssue.resolve(context(balance: .insufficientGas, move: .worsened(change: 1))), .notEnoughGas)
        XCTAssertEqual(SwapReworkIssue.resolve(context(balance: .insufficientFunds)), .overBalance)
        XCTAssertEqual(SwapReworkIssue.resolve(context(move: .worsened(change: dec("0.004")))), .priceMoved(.worsened(change: dec("0.004"))))
    }

    func testNothingWithoutAnAmountOrForCancellation() {
        var empty = context(balance: .insufficientFunds)
        empty.hasAmount = false
        XCTAssertNil(SwapReworkIssue.resolve(empty))
        XCTAssertNil(SwapReworkIssue.resolve(context(error: CancellationError())))
        XCTAssertNil(SwapReworkIssue.resolve(context()))
    }
}

final class SwapTrackerModelTests: XCTestCase {

    func testCrossChainStagesFollowStatus() {
        XCTAssertEqual(SwapTrackerModel.stages(status: .broadcasted(estimatedTime: ""), isCrossChain: true).map(\.status), [.active, .waiting, .waiting])
        XCTAssertEqual(SwapTrackerModel.stages(status: .pending, isCrossChain: true).map(\.status), [.done, .active, .waiting])
        XCTAssertEqual(SwapTrackerModel.stages(status: .confirmed, isCrossChain: true).map(\.status), [.done, .done, .done])
        XCTAssertEqual(SwapTrackerModel.stages(status: .failed(reason: "x"), isCrossChain: true).map(\.status), [.done, .failed, .waiting])
    }

    func testSameChainHasTwoStages() {
        XCTAssertEqual(SwapTrackerModel.stages(status: .pending, isCrossChain: false).map(\.kind), [.sent, .received])
    }

    func testPhaseAndRemainingRange() {
        XCTAssertEqual(SwapTrackerModel.phase(status: .pending, elapsed: 100, estimate: 600), .inProgress)
        XCTAssertEqual(SwapTrackerModel.phase(status: .pending, elapsed: 1000, estimate: 600), .takingLonger)
        XCTAssertEqual(SwapTrackerModel.phase(status: .timeout, elapsed: 0, estimate: nil), .takingLonger)
        XCTAssertEqual(SwapTrackerModel.remainingRange(elapsed: 120, estimate: 600), 6...10)
        XCTAssertNil(SwapTrackerModel.remainingRange(elapsed: 700, estimate: 600))
    }

    func testOutcomeQuotedVersusDelivered() {
        let outcome = SwapOutcome(quoted: dec("0.0140218"), delivered: dec("0.0140237"))
        XCTAssertTrue(outcome.isBetterThanQuoted)
        XCTAssertEqual(outcome.differenceInBaseUnits(decimals: 8), 190)
        XCTAssertEqual(outcome.differenceShareText, "+0.01%")
        XCTAssertEqual(SwapOutcome(quoted: 100, delivered: 99).differenceShareText, "-1.00%")
    }
}

final class SwapTokenTrustTests: XCTestCase {
    private let curated = [
        SwapTokenTrust.Token(chain: "Ethereum", ticker: "USDC", contract: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        SwapTokenTrust.Token(chain: "Ethereum", ticker: "ETH", contract: "")
    ]

    func testImpostorTickerIsUnverified() {
        let fake = SwapTokenTrust.Token(chain: "Ethereum", ticker: "usdc", contract: "0x9f3a51c0e2b84d7a6f0c3e9d1b2a4c5d6e7fc41b")
        XCTAssertEqual(SwapTokenTrust.assess(fake, curated: curated), .unverified(genuineContract: curated[0].contract))
    }

    func testGenuineNativeAndUnknownTickersAreVerified() {
        let genuine = SwapTokenTrust.Token(chain: "Ethereum", ticker: "USDC", contract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertEqual(SwapTokenTrust.assess(genuine, curated: curated), .verified)
        XCTAssertEqual(SwapTokenTrust.assess(.init(chain: "Ethereum", ticker: "ETH", contract: ""), curated: curated), .verified)
        XCTAssertEqual(SwapTokenTrust.assess(.init(chain: "Ethereum", ticker: "PEPE", contract: "0x1"), curated: curated), .verified)
        XCTAssertEqual(SwapTokenTrust.assess(.init(chain: "Base", ticker: "USDC", contract: "0x2"), curated: curated), .verified)
    }

    func testTokenClaimingANativeTickerIsUnverified() {
        let fakeEth = SwapTokenTrust.Token(chain: "Ethereum", ticker: "ETH", contract: "0xdead")
        XCTAssertEqual(SwapTokenTrust.assess(fakeEth, curated: curated), .unverified(genuineContract: ""))
    }

    func testOnlyHexContractsCompareIgnoringCase() {
        let solCurated = [SwapTokenTrust.Token(chain: "Solana", ticker: "USDC", contract: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")]
        let lowered = SwapTokenTrust.Token(chain: "Solana", ticker: "USDC", contract: "epjfwdd5aufqssqem2qn1xzybapc8g4weggkzwytdt1v")
        XCTAssertNotEqual(SwapTokenTrust.assess(lowered, curated: solCurated), .verified)
        XCTAssertTrue(SwapTokenTrust.sameContract("0xABC", "0xabc"))
        XCTAssertFalse(SwapTokenTrust.sameContract("", ""))
    }

    func testRecentsAreMostRecentFirstAndCapped() {
        XCTAssertEqual(SwapRecentTokens.merged(["a", "b", "c"], adding: "b", limit: 5), ["b", "a", "c"])
        XCTAssertEqual(SwapRecentTokens.merged(["a", "b", "c"], adding: "d", limit: 3), ["d", "a", "b"])
    }

    func testPickerFilterSortsByValueAndMatchesContractPrefix() {
        let rows = [
            row("ETH", chain: "Ethereum", fiat: "2512"),
            row("USDC", chain: "Ethereum", fiat: "2410", contract: "0xA0b8"),
            row("BTC", chain: "Bitcoin", fiat: "1477")
        ]
        XCTAssertEqual(SwapReworkPickerFilter.rows(rows, chainName: nil, query: "").map(\.asset.ticker), ["ETH", "USDC", "BTC"])
        XCTAssertEqual(SwapReworkPickerFilter.rows(rows, chainName: "Bitcoin", query: "").map(\.asset.ticker), ["BTC"])
        XCTAssertEqual(SwapReworkPickerFilter.rows(rows, chainName: nil, query: "0xa0").map(\.asset.ticker), ["USDC"])
        XCTAssertEqual(SwapReworkPickerFilter.chains(rows), ["Ethereum", "Bitcoin"])
    }

    private func row(_ ticker: String, chain: String, fiat: String, contract: String = "") -> SwapReworkPickerRow {
        SwapReworkPickerRow(
            asset: SwapReworkAsset(coinID: ticker, ticker: ticker, logo: "", chainLogo: nil, chainName: chain, isNative: contract.isEmpty),
            contract: contract, balanceText: "1", fiatText: "", fiatValue: dec(fiat), trust: .verified
        )
    }
}

final class SwapDeliveredAmountTests: XCTestCase {
    private let vaultBTC = "bc1qexamplevaultaddress0000000000000000"

    private func action(_ type: String, status: String = "success", inHash: String = "ABC123", out: [MidgardTransaction]) -> MidgardAction {
        MidgardAction(
            pools: [], type: type, status: status,
            in: [MidgardTransaction(txID: inHash, address: nil, coins: nil)],
            out: out, date: "0", height: "0", metadata: nil
        )
    }

    func testMidgardSumsSwapOutsToTheVaultInTheDestinationAsset() {
        let actions = [action("swap", out: [
            MidgardTransaction(txID: "OUT1", address: vaultBTC, coins: [MidgardCoin(asset: "BTC.BTC", amount: "1402370")]),
            MidgardTransaction(txID: "", address: "thor1affiliate", coins: [MidgardCoin(asset: "THOR.RUNE", amount: "99")])
        ])]
        let delivered = SwapDeliveredAmount.fromMidgard(
            actions: actions, count: "1", inboundHash: "0xabc123", recipient: vaultBTC.uppercased(),
            asset: "BTC.BTC", divisor: 100_000_000
        )
        XCTAssertEqual(delivered, dec("0.0140237"))
    }

    func testMidgardIgnoresRefundsAndOtherAssets() {
        let refunded = [
            action("swap", out: [MidgardTransaction(txID: "1", address: vaultBTC, coins: [MidgardCoin(asset: "BTC.BTC", amount: "10")])]),
            action("refund", out: [])
        ]
        XCTAssertNil(SwapDeliveredAmount.fromMidgard(actions: refunded, count: "2", inboundHash: "ABC123", recipient: vaultBTC, asset: "BTC.BTC", divisor: 1e8))
        // Same ticker, different contract: not the destination asset.
        let wrongContract = [action("swap", out: [MidgardTransaction(txID: "1", address: vaultBTC, coins: [MidgardCoin(asset: "ETH.USDC-0XFAKE", amount: "10")])])]
        XCTAssertNil(SwapDeliveredAmount.fromMidgard(actions: wrongContract, count: "1", inboundHash: "ABC123", recipient: vaultBTC, asset: "ETH.USDC-0XA0B8", divisor: 1e8))
        XCTAssertNil(SwapDeliveredAmount.fromMidgard(actions: [], count: "0", inboundHash: "ABC123", recipient: vaultBTC, asset: "BTC.BTC", divisor: 1e8))
    }

    func testMidgardRejectsTruncatedOrPendingPages() {
        let paid = [MidgardTransaction(txID: "1", address: vaultBTC, coins: [MidgardCoin(asset: "BTC.BTC", amount: "10")])]
        XCTAssertNil(SwapDeliveredAmount.fromMidgard(actions: [action("swap", out: paid)], count: "2", inboundHash: "ABC123", recipient: vaultBTC, asset: "BTC.BTC", divisor: 1e8))
        XCTAssertNil(SwapDeliveredAmount.fromMidgard(actions: [action("swap", status: "pending", out: paid)], count: "1", inboundHash: "ABC123", recipient: vaultBTC, asset: "BTC.BTC", divisor: 1e8))
        XCTAssertNil(SwapDeliveredAmount.fromMidgard(actions: [action("swap", out: paid)], count: "1", inboundHash: "ABC123", recipient: "", asset: "BTC.BTC", divisor: 1e8))
    }

    func testSecuredDenomMatchesIgnoringCase() {
        let paid = [MidgardTransaction(txID: "", address: "thor1vault", coins: [MidgardCoin(asset: "ETH-USDC-0XA0B8", amount: "250000000")])]
        XCTAssertEqual(SwapDeliveredAmount.fromMidgard(actions: [action("swap", out: paid)], count: "1", inboundHash: "ABC123", recipient: "thor1vault", asset: "eth-usdc-0xa0b8", divisor: 1e8), dec("2.5"))
    }

    func testReceiptSumsTokenTransfersToTheVault() {
        let token = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
        let vault = "0x9D2a7C1b3E4f5A6b7C8d9E0f1A2b3C4d5E6f3003"
        let vaultWord = SwapDeliveredAmount.topicWord(vault) ?? ""
        let other = SwapDeliveredAmount.topicWord("0x1111111111111111111111111111111111111111") ?? ""
        let logs = [
            SwapDeliveredAmount.Log(address: token.lowercased(), topics: [SwapDeliveredAmount.transferTopic, other, vaultWord], data: "0x3b9aca00"),
            SwapDeliveredAmount.Log(address: token, topics: [SwapDeliveredAmount.transferTopic, vaultWord, other], data: "0x10"),
            SwapDeliveredAmount.Log(address: "0xdead000000000000000000000000000000000000", topics: [SwapDeliveredAmount.transferTopic, other, vaultWord], data: "0x10")
        ]
        // 0x3b9aca00 = 1,000,000,000 base units = 1,000 USDC (6 decimals).
        XCTAssertEqual(SwapDeliveredAmount.fromReceiptLogs(logs, token: token, recipient: vault, decimals: 6), 1000)
        XCTAssertNil(SwapDeliveredAmount.fromReceiptLogs([], token: token, recipient: vault, decimals: 6))
        XCTAssertNil(SwapDeliveredAmount.fromReceiptLogs(logs, token: "", recipient: vault, decimals: 6))
    }

    func testApprovalGasLegs() {
        XCTAssertEqual(SwapApprovalGas.legs(for: .notRequired), 0)
        XCTAssertEqual(SwapApprovalGas.legs(for: .approve), 1)
        XCTAssertEqual(SwapApprovalGas.legs(for: .resetThenApprove), 2)
        XCTAssertEqual(SwapApprovalGas.fiat(legs: 2, perLegFiat: dec("1.06")), dec("2.12"))
        XCTAssertEqual(SwapApprovalGas.totalGas(swapGas: dec("0.00054"), legs: 1), dec("0.00108"))
    }

    func testApprovalGasCountsInTotalsAndDebit() {
        let fees = SwapFeeBreakdown(.init(
            networkFiat: dec("1.06"), networkCrypto: "", approvalFiat: dec("1.06"), protocolFiat: 0,
            vultisigNetFiat: dec("3.00"), vultisigListFiat: dec("5.00"), listBps: 50, tierDiscountBps: 20,
            tier: .gold, vultisigIncludedInRate: false, payFiat: 1000, receiveFiat: dec("996.60")
        ))
        XCTAssertEqual(fees.totalFiat, dec("5.12"))
        XCTAssertEqual(fees.displayTotalFiat, dec("5.12"))
        XCTAssertEqual(fees.totalDebitFiat, dec("1002.12"))
        XCTAssertEqual(fees.allInChangeText, "-0.55%")
    }
}
