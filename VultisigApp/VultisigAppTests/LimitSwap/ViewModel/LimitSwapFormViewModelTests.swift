//
//  LimitSwapFormViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class LimitSwapFormViewModelTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var quoteService: MockLimitSwapQuoteService!
    private var interactor: DefaultLimitSwapInteractor!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()

        // Vault holds matching coins for source (BTC) + target (ETH) so
        // destinationAddress() can resolve.
        let btc = Coin(
            asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8),
            address: "bc1qsourceaddress0000000000000000000000000",
            hexPublicKey: "btc-pubkey"
        )
        // Funded well above every fixture amount so tests that are about a
        // DIFFERENT `canPlaceOrder` term aren't silently blocked by the balance
        // gate. The balance-specific tests set their own balances.
        btc.rawBalance = "1000000000"  // 10 BTC
        vault.coins.append(btc)
        let eth = Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: "ETH", decimals: 18),
            address: "0xethdestaddress00000000000000000000000000",
            hexPublicKey: "eth-pubkey"
        )
        eth.rawBalance = "1000000000000000000"  // 1 ETH
        vault.coins.append(eth)

        quoteService = MockLimitSwapQuoteService()
        interactor = DefaultLimitSwapInteractor(quoteService: quoteService)
    }

    override func tearDown() async throws {
        interactor = nil
        quoteService = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - input mutations

    func testAmountChangedUpdatesDraft() {
        let vm = makeViewModel()
        vm.amountChanged(BigInt(50_000_000))
        XCTAssertEqual(vm.draft.sourceAmount, BigInt(50_000_000))
    }

    func testTargetPriceChangedUpdatesDraft() {
        let vm = makeViewModel()
        vm.targetPriceChanged(Decimal(string: "16.5")!)
        XCTAssertEqual(vm.draft.targetPrice, Decimal(string: "16.5")!)
    }

    // MARK: - USD-denominated target price edit

    func testTargetPriceChangedFromUsdConvertsToAssetTerms() {
        // USD editing stores the canonical price in TARGET-ASSET terms, not USD.
        // rate = $2 per target unit; editing $6000 → 3000 target units per source.
        let vm = makeViewModel()
        vm.targetUsdPricePerUnit = 2
        vm.targetPriceChangedFromUsd(6000)
        XCTAssertEqual(vm.draft.targetPrice, 3000)
    }

    func testTargetPriceChangedFromUsdRoundTripsWithDisplay() {
        // Editing USD then re-deriving the USD display (targetPrice × rate) must
        // return the same USD value — the display and the edit are exact inverses.
        let vm = makeViewModel()
        vm.targetUsdPricePerUnit = Decimal(string: "1.5")!
        vm.targetPriceChangedFromUsd(4500)
        XCTAssertEqual(vm.draft.targetPrice, 3000)
        XCTAssertEqual(vm.draft.targetPrice * vm.targetUsdPricePerUnit, 4500)
    }

    func testTargetPriceChangedFromUsdRoundsToEightDecimals() {
        // The stored price must never carry more than the memo LIM's 8-dp
        // precision, so the asset-text mirror round-trips it exactly (no feedback
        // rounding of the canonical price). $1 at $3/unit → 0.33333333.
        let vm = makeViewModel()
        vm.targetUsdPricePerUnit = 3
        vm.targetPriceChangedFromUsd(1)
        XCTAssertEqual(vm.draft.targetPrice, Decimal(string: "0.33333333")!)
    }

    func testTargetPriceChangedFromUsdIsNoOpWithoutRate() {
        // No USD rate → USD editing is disabled; the canonical price must not move
        // (and must NEVER be set to the raw USD number).
        let vm = makeViewModel()
        vm.targetUsdPricePerUnit = 0
        vm.draft.targetPrice = 42
        vm.targetPriceChangedFromUsd(6000)
        XCTAssertEqual(vm.draft.targetPrice, 42)
    }

    // MARK: - percent-from-market offset (chip readout + custom-offset sheet)

    func testPctFromMarketChangedSetsPriceRelativeToMarket() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.pctFromMarketChanged(5)
        XCTAssertEqual(vm.draft.targetPrice, 105)
    }

    func testPctFromMarketChangedAcceptsFractionalOffsets() {
        // The whole point of the custom sheet over the pills: an offset the
        // presets don't offer.
        let vm = makeViewModel()
        vm.marketPriceRef = 200
        vm.pctFromMarketChanged(Decimal(string: "7.5")!)
        XCTAssertEqual(vm.draft.targetPrice, 215)
    }

    func testPctFromMarketChangedAcceptsNegativeOffsets() {
        // A below-market target is legitimate — it fills as soon as it rests —
        // and is explained by the `priceAtOrBelowMarket` warning, not blocked.
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.pctFromMarketChanged(-3)
        XCTAssertEqual(vm.draft.targetPrice, 97)
        XCTAssertEqual(vm.displayedWarning, .priceAtOrBelowMarket)
    }

    func testPctFromMarketChangedIsNoOpWithoutMarketReference() {
        // An offset has nothing to offset from; the price must not move.
        let vm = makeViewModel()
        vm.marketPriceRef = nil
        vm.draft.targetPrice = 42
        vm.pctFromMarketChanged(5)
        XCTAssertEqual(vm.draft.targetPrice, 42)
    }

    func testPctFromMarketChangedRoundsToEightDecimals() {
        // Same rule as every other price-setting path: never store more precision
        // than the signed memo's 1e8 LIM can express.
        let vm = makeViewModel()
        vm.marketPriceRef = Decimal(string: "0.123456789")!
        vm.pctFromMarketChanged(1)

        var rounded = Decimal()
        var value = vm.draft.targetPrice
        NSDecimalRound(&rounded, &value, 8, .plain)
        XCTAssertEqual(vm.draft.targetPrice, rounded)
    }

    func testPctFromMarketRoundTripsThroughPctFromMarketChanged() {
        // The sheet writes and the chip reads back: what `pctFromMarket` reports
        // must be what was set, or the readout and the control disagree.
        let vm = makeViewModel()
        vm.marketPriceRef = 250
        vm.pctFromMarketChanged(Decimal(string: "12.5")!)
        XCTAssertEqual(vm.pctFromMarket, Decimal(string: "12.5")!)
    }

    func testTargetPriceForPctIsNilWithoutMarketReference() {
        let vm = makeViewModel()
        vm.marketPriceRef = nil
        XCTAssertNil(vm.targetPrice(forPctFromMarket: 5))
    }

    func testAnOffsetInsideTheStepperRangeCanStillResolveToAZeroPrice() {
        // Why the custom-offset sheet refuses on the resolved PRICE rather than on
        // the offset: the stepper's floor keeps `pct` a whole percent clear of
        // -100%, but the price it resolves to is rounded to the memo LIM's 8
        // decimals — and against a small enough market (a sub-cent token quoted in
        // BTC) a perfectly legal offset still lands on zero. A zero LIM tells
        // THORChain "fill at ANY price", so no fixed percentage floor can be the
        // guard.
        let vm = makeViewModel()
        vm.marketPriceRef = Decimal(string: "0.0000004")!
        XCTAssertEqual(vm.targetPrice(forPctFromMarket: limitPctOffsetRange.lowerBound), 0)
    }

    func testTargetPriceForPctMatchesWhatPctFromMarketChangedStores() {
        // The sheet previews the price an offset resolves to through this
        // function, then applies it through the setter. If the two disagreed, the
        // sheet would show one price and place another.
        let vm = makeViewModel()
        vm.marketPriceRef = Decimal(string: "27.4218")!
        let pct = Decimal(string: "7.555")!

        let mapped = vm.targetPrice(forPctFromMarket: pct)
        vm.pctFromMarketChanged(pct)

        XCTAssertEqual(mapped, vm.draft.targetPrice)
    }

    func testExternalPriceChangeRebasesTheOffsetReadout() {
        // The chip reads `pctFromMarket` live rather than holding a value of its
        // own, so a price moved by something else — a chart drag here — has to
        // show up in the offset immediately.
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.pctFromMarketChanged(5)
        XCTAssertEqual(vm.pctFromMarket, 5)

        vm.targetPriceChangedFromChart(140)
        XCTAssertEqual(vm.pctFromMarket, 40)
    }

    func testMarketReferenceMovingRebasesTheOffsetReadout() {
        // Same property, different cause: a fresh quote re-bases the offset while
        // the target price stands still. A chip left reading "+5.00%" would be
        // describing the OLD market.
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.pctFromMarketChanged(5)
        XCTAssertEqual(vm.draft.targetPrice, 105)

        vm.marketPriceRef = 105
        XCTAssertEqual(vm.pctFromMarket, 0)
    }

    func testPresetPillAndCustomOffsetProduceTheSamePrice() {
        // The pills are shortcuts into the same arithmetic — if these ever
        // diverge, tapping +5% and stepping to +5% would place different orders.
        let viaPill = makeViewModel()
        viaPill.marketPriceRef = Decimal(string: "27.4218")!
        viaPill.selectPresetPct(5)

        let viaSheet = makeViewModel()
        viaSheet.marketPriceRef = Decimal(string: "27.4218")!
        viaSheet.pctFromMarketChanged(5)

        XCTAssertEqual(viaPill.draft.targetPrice, viaSheet.draft.targetPrice)
    }

    // MARK: - two-way amounts (the driver rule)

    func testTypingSellMakesSellTheDriver() {
        let vm = makeViewModel()
        vm.draft.targetPrice = 16
        vm.amountChanged(BigInt(100_000_000))
        XCTAssertEqual(vm.draft.amountDriver, .sell)
    }

    func testTypingBuyDerivesTheSellAmount() {
        let vm = makeViewModel()
        vm.draft.targetPrice = 16
        vm.buyAmountChanged(16)  // want 16 ETH at 16 ETH/BTC → 1 BTC
        XCTAssertEqual(vm.draft.amountDriver, .buy)
        XCTAssertEqual(vm.draft.sourceAmount, BigInt(100_000_000))
    }

    func testPriceChangeMovesTheSellSideWhenBuyIsDriving() {
        // The rule's whole point: "I want 16 ETH" survives a price change, and
        // what it COSTS is what moves.
        let vm = makeViewModel()
        vm.draft.targetPrice = 16
        vm.buyAmountChanged(16)
        XCTAssertEqual(vm.draft.sourceAmount, BigInt(100_000_000))

        vm.targetPriceChanged(8)  // half the price → twice the deposit
        XCTAssertEqual(vm.draft.sourceAmount, BigInt(200_000_000))
        XCTAssertEqual(vm.draft.desiredTargetOutput, 16, "the stated output must not drift")
    }

    func testPriceChangeMovesTheBuySideWhenSellIsDriving() {
        let vm = makeViewModel()
        vm.draft.targetPrice = 16
        vm.amountChanged(BigInt(100_000_000))
        XCTAssertEqual(vm.expectedBuyAmount, 16)

        vm.targetPriceChanged(8)
        XCTAssertEqual(vm.draft.sourceAmount, BigInt(100_000_000), "the stated deposit must not drift")
        XCTAssertEqual(vm.expectedBuyAmount, 8)
    }

    func testPresetPillAlsoHonoursTheDriver() {
        // Presets assign the price directly instead of going through
        // `targetPriceChanged`, so without an explicit call there the rule would
        // hold for typing and silently break for tapping.
        let vm = makeViewModel()
        vm.marketPriceRef = 16
        vm.draft.targetPrice = 16
        vm.buyAmountChanged(16)
        let before = vm.draft.sourceAmount

        vm.selectPresetPct(100)  // price doubles → the same output costs half
        XCTAssertEqual(vm.draft.desiredTargetOutput, 16)
        XCTAssertLessThan(vm.draft.sourceAmount, before)
    }

    func testBuyDrivenEntryNeverOverstatesTheGuaranteedOutput() {
        // A typed output may settle slightly lower after the deposit truncates —
        // that is the order's real minimum. It must never settle HIGHER.
        let vm = makeViewModel()
        vm.draft.targetPrice = Decimal(string: "3.7")!
        vm.buyAmountChanged(10)
        XCTAssertLessThanOrEqual(vm.expectedBuyAmount, 10)
    }

    func testChangingTheTargetAssetHandsControlBackToSell() {
        // The stated output referred to the OLD target asset.
        let vm = makeViewModel()
        vm.draft.targetPrice = 16
        vm.buyAmountChanged(16)
        XCTAssertEqual(vm.draft.amountDriver, .buy)

        vm.selectToAsset(ethAsset())
        XCTAssertEqual(vm.draft.amountDriver, .sell)
        XCTAssertEqual(vm.draft.desiredTargetOutput, 0)
    }

    func testChangingTheSourceAssetHandsControlBackToSell() {
        // A derived deposit was scaled to the OLD source's decimals.
        let vm = makeViewModel()
        vm.draft.targetPrice = 16
        vm.buyAmountChanged(16)

        vm.selectFromAsset(btcAsset())
        XCTAssertEqual(vm.draft.amountDriver, .sell)
        XCTAssertEqual(vm.draft.desiredTargetOutput, 0)
    }

    func testBuyDrivenAmountInvalidatesTheNetworkFee() {
        // The deposit changed, so a fee estimated against the previous one must
        // not be snapshotted into the order.
        let vm = makeViewModel()
        vm.draft.targetPrice = 16
        vm.networkFeeEstimate = BigInt(4_200)
        vm.buyAmountChanged(16)
        XCTAssertEqual(vm.networkFeeEstimate, .zero)
    }

    func testAnUnchangedDerivedDepositKeepsTheFeeEstimate() {
        // The fee refresh is driven by an observer on `draft.sourceAmount`. If a
        // derived write zeroed the estimate WITHOUT moving the deposit, nothing
        // would observe a change, no replacement would be scheduled, and the CTA
        // — which requires a resolved fee — would stay disabled forever.
        let vm = makeViewModel()
        vm.draft.targetPrice = 16
        vm.buyAmountChanged(16)
        let deposit = vm.draft.sourceAmount
        vm.networkFeeEstimate = BigInt(4_200)

        // Re-stating the same output derives the same deposit.
        vm.buyAmountChanged(16)

        XCTAssertEqual(vm.draft.sourceAmount, deposit)
        XCTAssertEqual(vm.networkFeeEstimate, BigInt(4_200), "an unchanged deposit must not strand the fee at zero")
    }

    func testCanPlaceOrderRejectsADepositThatFloorsTheLimToZero() async {
        // A positive deposit isn't enough: computeLim truncates again into 1e8
        // fixed point, so dust at a low price yields LIM = 0 and throws at memo
        // build. The CTA must not enable for an order that can only fail.
        let vm = await makeReadyToPlace(sourceAmount: BigInt(1))
        vm.draft.targetPrice = Decimal(string: "0.00000001")!

        XCTAssertEqual(vm.expectedBuyAmount, 0, "precondition: this amount/price yields no derivable output")
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()))
    }

    // MARK: - expiry

    func testSelectExpiryBlocksUpdatesDraft() {
        let vm = makeViewModel()
        vm.selectExpiryBlocks(THORChainConstants.blocks(forHours: 72))
        XCTAssertEqual(vm.draft.expiryBlocks, THORChainConstants.blocks(forHours: 72))
    }

    func testSelectExpiryBlocksAcceptsAnArbitraryDuration() {
        // 90 minutes was unreachable before: the old setter took whole hours and
        // validation whitelisted {12, 24, 72}.
        let vm = makeViewModel()
        vm.selectExpiryBlocks(THORChainConstants.blocks(forMinutes: 90))
        XCTAssertEqual(vm.draft.expiryBlocks, THORChainConstants.blocks(forMinutes: 90))
    }

    func testSelectExpiryBlocksClampsToTheCeiling() {
        // THORChain clamps an over-long TTL silently, so the form has to clamp on
        // the way in — otherwise the pill row would advertise a window the queue
        // never grants.
        let vm = makeViewModel()
        vm.maxExpiryBlocks = THORChainConstants.defaultLimitSwapMaxAgeBlocks
        vm.selectExpiryBlocks(THORChainConstants.blocks(forHours: 24 * 7))
        XCTAssertEqual(vm.draft.expiryBlocks, THORChainConstants.defaultLimitSwapMaxAgeBlocks)
    }

    func testSelectExpiryBlocksClampsToTheFloor() {
        let vm = makeViewModel()
        vm.selectExpiryBlocks(1)
        XCTAssertEqual(vm.draft.expiryBlocks, THORChainConstants.minLimitSwapAgeBlocks)
    }

    func testRefreshMaxExpiryAdoptsTheMimirValue() async {
        let interactor = MockLimitSwapInteractor()
        interactor.limitSwapMaxAgeResult = 21_600
        let vm = makeViewModel(interactor: interactor)

        await vm.refreshMaxExpiry()

        XCTAssertEqual(vm.maxExpiryBlocks, 21_600)
    }

    func testRefreshMaxExpiryReClampsADraftTheNewCeilingInvalidates() async {
        // The case that matters: the draft was seeded against the DEFAULT ceiling,
        // then the live mimir turns out to be lower. Without the re-clamp the form
        // would keep showing 3d while the chain would shorten it to 1.5d.
        let interactor = MockLimitSwapInteractor()
        interactor.limitSwapMaxAgeResult = 21_600
        let vm = makeViewModel(interactor: interactor)
        vm.draft.expiryBlocks = THORChainConstants.defaultLimitSwapMaxAgeBlocks

        await vm.refreshMaxExpiry()

        XCTAssertEqual(vm.draft.expiryBlocks, 21_600)
    }

    func testRefreshMaxExpiryLeavesAStillValidDraftAlone() async {
        // A RAISED ceiling never invalidates an existing choice.
        let interactor = MockLimitSwapInteractor()
        interactor.limitSwapMaxAgeResult = THORChainConstants.defaultLimitSwapMaxAgeBlocks * 2
        let vm = makeViewModel(interactor: interactor)
        let chosen = THORChainConstants.blocks(forHours: 24)
        vm.draft.expiryBlocks = chosen

        await vm.refreshMaxExpiry()

        XCTAssertEqual(vm.draft.expiryBlocks, chosen)
    }

    func testToggleDisplayUnitFlipsBetweenAssetAndUsd() {
        let vm = makeViewModel(initialDisplayUnit: .asset)
        vm.toggleDisplayUnit()
        XCTAssertEqual(vm.draft.displayUnit, .usd)
        vm.toggleDisplayUnit()
        XCTAssertEqual(vm.draft.displayUnit, .asset)
    }

    // MARK: - preset pills

    func testSelectPresetPctMarketAlignsTargetWithMarketPrice() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.selectPresetPct(0)
        XCTAssertEqual(vm.draft.targetPrice, 100)
    }

    func testSelectPresetPctOnePercentAddsOnePercent() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.selectPresetPct(1)
        XCTAssertEqual(vm.draft.targetPrice, 101)
    }

    func testSelectPresetPctTenPercentAddsTenPercent() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.selectPresetPct(10)
        XCTAssertEqual(vm.draft.targetPrice, 110)
    }

    func testSelectPresetPctIsNoOpWhenMarketReferenceMissing() {
        let vm = makeViewModel()
        vm.marketPriceRef = nil
        vm.draft.targetPrice = 50
        vm.selectPresetPct(5)
        XCTAssertEqual(vm.draft.targetPrice, 50, "Preset must not act without a market reference")
    }

    // MARK: - asset selection invalidates market reference

    func testSelectFromAssetClearsMarketPriceReference() {
        let vm = makeViewModel()
        vm.marketPriceRef = 16
        vm.selectFromAsset(LimitSwapAsset(
            chain: .litecoin, ticker: "LTC", decimals: 8,
            contractAddress: "", isNativeToken: true
        ))
        XCTAssertNil(vm.marketPriceRef)
    }

    func testSelectToAssetClearsMarketPriceReference() {
        let vm = makeViewModel()
        vm.marketPriceRef = 16
        vm.selectToAsset(LimitSwapAsset(
            chain: .thorChain, ticker: "RUNE", decimals: 8,
            contractAddress: "", isNativeToken: true
        ))
        XCTAssertNil(vm.marketPriceRef)
    }

    // MARK: - computed UI state

    func testPctFromMarketIsZeroWhenMarketReferenceMissing() {
        let vm = makeViewModel()
        vm.marketPriceRef = nil
        vm.draft.targetPrice = 100
        XCTAssertEqual(vm.pctFromMarket, 0)
    }

    func testPctFromMarketComputesCorrectPercentage() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.draft.targetPrice = 105
        XCTAssertEqual(vm.pctFromMarket, 5)
    }

    func testDisplayedWarningIsNilWithoutMarketReference() {
        let vm = makeViewModel()
        vm.marketPriceRef = nil
        vm.draft.targetPrice = 50
        XCTAssertNil(vm.displayedWarning)
    }

    func testDisplayedWarningTriggersAtOrBelowMarket() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.draft.targetPrice = 95
        XCTAssertEqual(vm.displayedWarning, .priceAtOrBelowMarket)
    }

    func testDisplayedWarningTriggersFarAboveMarket() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.draft.targetPrice = 121
        XCTAssertEqual(vm.displayedWarning, .priceFarAboveMarket)
    }

    func testDisplayedWarningIsNilInTheReasonableBand() {
        let vm = makeViewModel()
        vm.marketPriceRef = 100
        vm.draft.targetPrice = 110
        XCTAssertNil(vm.displayedWarning)
    }

    // MARK: - refreshMarketPrice

    func testRefreshMarketPriceStoresFetchedValue() async {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        quoteService.marketPriceResult = .success(Decimal(string: "16.5")!)

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.marketPriceRef, Decimal(string: "16.5")!)
        XCTAssertNil(vm.marketPriceError)
        XCTAssertFalse(vm.isLoadingMarketPrice)
        XCTAssertEqual(quoteService.marketPriceCallCount, 1)
    }

    func testRefreshMarketPriceFailureSurfacesErrorAndPreservesPreviousReference() async {
        struct UpstreamError: Error {}

        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.marketPriceRef = 16
        quoteService.marketPriceResult = .failure(UpstreamError())

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.marketPriceRef, 16, "Previous reference must be preserved on failure")
        XCTAssertNotNil(vm.marketPriceError)
        XCTAssertFalse(vm.isLoadingMarketPrice)
    }

    func testRefreshMarketPriceFallsBackToOneUnitWhenSourceAmountIsZeroWithoutRate() async {
        // Phase-1 behaviour: the view kicks `refreshMarketPrice()` on appear
        // before the user has typed anything, so the VM substitutes a probe
        // quote rather than early-returning. With no source USD rate the probe
        // falls back to a 1-unit (`10^sourceDecimals`) quote.
        let vm = makeViewModel(sourceAmount: 0)
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.marketPriceRef, 99)
        XCTAssertEqual(quoteService.marketPriceCallCount, 1)
        XCTAssertEqual(quoteService.marketPriceAmounts.first, BigInt(10).power(8),
                       "Without a USD rate the probe must fall back to 1 whole unit")
    }

    func testRefreshMarketPriceProbesFiatNotionalWhenSourceAmountIsZero() async {
        // The bug: a cheap source (e.g. RUNE) at 0 amount probed with 1 whole
        // unit, which THORChain rejects (outbound fee > output) so no reference
        // ever loaded. With a source USD rate the probe is sized to ~$100 of the
        // source instead — here $2/unit BTC-decimals → 50 units × 1e8.
        let vm = makeViewModel(sourceAmount: 0)
        vm.sourceUsdPricePerUnit = 2
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        XCTAssertEqual(quoteService.marketPriceAmounts.first, BigInt(5_000_000_000))
    }

    func testRefreshMarketPriceUsesTypedAmountOverProbe() async {
        // Once the user has typed an amount it is used verbatim, ignoring the
        // notional probe / source price.
        let vm = makeViewModel(sourceAmount: BigInt(777))
        vm.sourceUsdPricePerUnit = 2
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        XCTAssertEqual(quoteService.marketPriceAmounts.first, BigInt(777))
    }

    func testRefreshMarketPriceFailsWhenTargetChainHasNoVaultCoin() async {
        // Replace the vault's ETH coin with a chain not represented (LTC),
        // so destinationAddress() returns nil for the .ethereum target.
        vault.coins.removeAll(where: { $0.chain == .ethereum })

        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        quoteService.marketPriceResult = .success(99)

        await vm.refreshMarketPrice()

        guard case LimitSwapFormViewModel.ViewModelError.noDestinationAddressForTargetChain = vm.marketPriceError ?? UntestedError() else {
            return XCTFail("Expected noDestinationAddressForTargetChain")
        }
        XCTAssertNil(vm.marketPriceRef)
    }

    // MARK: - refreshNetworkFeeEstimate (limit network-fee estimate)

    func testRefreshNetworkFeeEstimateSkippedWhenAmountIsZero() async {
        let mockInteractor = MockLimitSwapInteractor()
        mockInteractor.networkFeeResult = .success(BigInt(4_200))
        let vm = makeViewModel(interactor: mockInteractor, sourceAmount: 0)

        await vm.refreshNetworkFeeEstimate(sourceCoin: btcCoin(), targetCoin: ethCoin())

        XCTAssertEqual(mockInteractor.estimateNetworkFeeCallCount, 0, "No estimate is needed before an amount is entered")
        XCTAssertEqual(vm.networkFeeEstimate, .zero)
    }

    func testRefreshNetworkFeeEstimateStoresInteractorResult() async {
        let mockInteractor = MockLimitSwapInteractor()
        mockInteractor.networkFeeResult = .success(BigInt(4_200))
        let vm = makeViewModel(interactor: mockInteractor, sourceAmount: BigInt(100_000_000))

        await vm.refreshNetworkFeeEstimate(sourceCoin: btcCoin(), targetCoin: ethCoin())

        XCTAssertEqual(mockInteractor.estimateNetworkFeeCallCount, 1)
        XCTAssertEqual(mockInteractor.estimateNetworkFeeAmounts.first, BigInt(100_000_000),
                       "The estimate must be sized to the real (placed) amount")
        XCTAssertEqual(vm.networkFeeEstimate, BigInt(4_200))
    }

    func testInputChangesClearStaleNetworkFeeEstimate() {
        // A fee estimate must never survive a source/target/amount change — else a
        // previous pair/amount's fee could be snapshotted into the placed order.
        let vm = makeViewModel()

        vm.networkFeeEstimate = BigInt(111)
        vm.amountChanged(BigInt(5))
        XCTAssertEqual(vm.networkFeeEstimate, .zero, "amountChanged must clear the estimate")

        vm.networkFeeEstimate = BigInt(222)
        vm.selectFromAsset(LimitSwapAsset(chain: .litecoin, ticker: "LTC", decimals: 8, contractAddress: "", isNativeToken: true))
        XCTAssertEqual(vm.networkFeeEstimate, .zero, "selectFromAsset must clear the estimate")

        vm.networkFeeEstimate = BigInt(333)
        vm.selectToAsset(LimitSwapAsset(chain: .thorChain, ticker: "RUNE", decimals: 8, contractAddress: "", isNativeToken: true))
        XCTAssertEqual(vm.networkFeeEstimate, .zero, "selectToAsset must clear the estimate")
    }

    func testRefreshNetworkFeeEstimateKeepsPreviousEstimateOnFailure() async {
        struct UpstreamError: Error {}
        let mockInteractor = MockLimitSwapInteractor()
        mockInteractor.networkFeeResult = .failure(UpstreamError())
        let vm = makeViewModel(interactor: mockInteractor, sourceAmount: BigInt(100_000_000))
        vm.networkFeeEstimate = BigInt(999)  // a prior successful estimate

        await vm.refreshNetworkFeeEstimate(sourceCoin: btcCoin(), targetCoin: ethCoin())

        XCTAssertEqual(vm.networkFeeEstimate, BigInt(999), "A transient fetch failure must not zero the estimate")
    }

    // MARK: - refreshSupportedChains (routed through the injected interactor)

    func testRefreshSupportedChainsUsesInjectedInteractor() async {
        quoteService.inboundAddressesResult = [
            InboundAddress(
                chain: "BTC", address: "a", router: nil, halted: false,
                global_trading_paused: false, chain_trading_paused: false,
                chain_lp_actions_paused: false, gas_rate: "0", gas_rate_units: "u",
                dust_threshold: nil, outbound_fee: nil, outbound_tx_size: nil
            ),
            InboundAddress(
                chain: "ETH", address: "b", router: nil, halted: false,
                global_trading_paused: false, chain_trading_paused: false,
                chain_lp_actions_paused: false, gas_rate: "0", gas_rate_units: "u",
                dust_threshold: nil, outbound_fee: nil, outbound_tx_size: nil
            )
        ]
        let vm = makeViewModel()

        await vm.refreshSupportedChains()

        XCTAssertEqual(quoteService.inboundAddressesCallCount, 1)
        let supported = vm.supportedChains ?? []
        XCTAssertTrue(supported.contains(.thorChain))
        XCTAssertTrue(supported.contains(.bitcoin))
        XCTAssertTrue(supported.contains(.ethereum))
    }

    // MARK: - destinationAddress lookup

    func testDestinationAddressFindsMatchingVaultCoin() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.destinationAddress(), "0xethdestaddress00000000000000000000000000")
    }

    // MARK: - preparePlaceableOrder (the live place-order gate)

    func testPreparePlaceableOrderBuildsRecordAndMemoForValidDraft() async {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.draft.expiryBlocks = THORChainConstants.blocks(forHours: 24)
        vm.marketPriceRef = 16  // positive routability proof (resolved quote)

        guard let prepared = vm.preparePlaceableOrder() else {
            return XCTFail("Expected a prepared order for a valid draft")
        }

        XCTAssertNil(vm.placeOrderError)
        // Memo prefix / affiliate are stable regardless of LIM encoding.
        XCTAssertTrue(prepared.memo.hasPrefix("=<:ETH.ETH:0xethdestaddress00000000000000000000000000:"))
        XCTAssertTrue(prepared.memo.contains(":\(THORChainSwaps.affiliateFeeAddress):"))

        let record = prepared.record
        XCTAssertEqual(record.sourceAsset, "BTC.BTC")
        XCTAssertEqual(record.targetAsset, "ETH.ETH")
        XCTAssertEqual(record.destAddress, "0xethdestaddress00000000000000000000000000")
        XCTAssertEqual(record.targetPrice, 16)
        XCTAssertEqual(record.expiryBlocks, THORChainConstants.blocks(forHours: 24))
        XCTAssertEqual(record.expiryBlocks, 14_400)
        XCTAssertEqual(record.sourceAmount, "100000000")
        XCTAssertEqual(record.status, .pending)
        XCTAssertTrue(record.inboundTxHash.isEmpty, "Inbound hash is spliced in later on the Done screen")
        XCTAssertEqual(record.memo, prepared.memo)
    }

    func testPreparePlaceableOrderAcceptsNonNativeErc20Source() async {
        // ERC20 sources are supported: the order assembles (memo + record) and
        // the keysign path builds approve(router) + router depositWithExpiry.
        // (The old native-only gate has been removed.)
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.fromAsset = LimitSwapAsset(
            chain: .ethereum, ticker: "USDC", decimals: 6,
            contractAddress: "0x1234567890abcdefEC7", isNativeToken: false
        )
        vm.draft.toAsset = LimitSwapAsset(
            chain: .bitcoin, ticker: "BTC", decimals: 8,
            contractAddress: "", isNativeToken: true
        )
        // Vault needs a BTC coin as the destination for the .bitcoin target.
        vault.coins.append(Coin(
            asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8),
            address: "bc1qdest0000000000000000000000000000000000",
            hexPublicKey: "btc-dest-pubkey"
        ))
        vm.draft.targetPrice = Decimal(string: "0.00002")!
        vm.marketPriceRef = Decimal(string: "0.00002")!  // positive routability proof

        let prepared = vm.preparePlaceableOrder()
        XCTAssertNotNil(prepared, "ERC20 source should now assemble a placeable order")
        XCTAssertNil(vm.placeOrderError)
        XCTAssertTrue(prepared?.record.sourceAsset.hasPrefix("ETH.USDC-") ?? false)
        XCTAssertTrue(prepared?.memo.hasPrefix("=<:BTC.BTC:") ?? false)
    }

    // MARK: - ERC20 limit approve consent (isApproveRequired / isValidForm)

    private func limitTransaction(sourceIsErc20: Bool) -> SwapTransaction {
        let fromCoin = sourceIsErc20
            ? Coin(asset: CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false),
                   address: "0xsource0000000000000000000000000000000000", hexPublicKey: "pk")
            : Coin(asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8),
                   address: "bc1qsource0000000000000000000000000000000", hexPublicKey: "pk")
        let toCoin = Coin(asset: CoinMeta.make(chain: .thorChain, ticker: "RUNE", decimals: 8),
                          address: "thor1destination", hexPublicKey: "pk")
        let feeCoin = sourceIsErc20
            ? Coin(asset: CoinMeta.make(chain: .ethereum, ticker: "ETH", decimals: 18),
                   address: "0xfee00000000000000000000000000000000000000", hexPublicKey: "pk")
            : fromCoin
        let record = LimitOrderRecord(
            inboundTxHash: "",
            sourceAsset: sourceIsErc20 ? "ETH.USDC-EC7" : "BTC.BTC",
            sourceAmount: "1000000",
            sourceDecimals: fromCoin.decimals,
            targetAsset: "THOR.RUNE",
            destAddress: "thor1destination",
            targetPrice: Decimal(string: "2.5")!,
            expiryBlocks: 14_400,
            memo: "=<:THOR.RUNE:thor1destination:1/14400/0:vi:50"
        )
        return SwapTransaction(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: 1,
            kind: .limit(record),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            networkFeeEstimate: BigInt(1_000_000_000_000_000),
            feeCoin: feeCoin,
            advancedSettings: .default
        )
    }

    func testErc20LimitOrderRequiresApproveConfirmation() {
        // An ERC20 source attaches approve(router), so the approve checkbox must
        // surface — even though a limit order carries no market quote.
        XCTAssertTrue(limitTransaction(sourceIsErc20: true).isApproveRequired)
        // A native source has no approve.
        XCTAssertFalse(limitTransaction(sourceIsErc20: false).isApproveRequired)
    }

    func testErc20LimitFormGatesSigningOnAmountFeeAndApprove() {
        let tx = limitTransaction(sourceIsErc20: true)
        let vm = SwapVerifyViewModel(transaction: tx)
        vm.isAmountCorrect = true
        vm.isFeeCorrect = true
        vm.isApproveCorrect = false
        XCTAssertFalse(vm.isValidForm(shouldApprove: tx.isApproveRequired),
                       "the bundled ERC20 approve must gate signing on the approve checkbox")
        vm.isApproveCorrect = true
        XCTAssertTrue(vm.isValidForm(shouldApprove: tx.isApproveRequired))
    }

    func testNativeLimitFormGatesSigningOnAmountAndFee() {
        let tx = limitTransaction(sourceIsErc20: false)
        let vm = SwapVerifyViewModel(transaction: tx)
        vm.isAmountCorrect = true
        vm.isFeeCorrect = false
        XCTAssertFalse(vm.isValidForm(shouldApprove: tx.isApproveRequired),
                       "the network-fee checkbox must gate signing for limit orders")
        vm.isFeeCorrect = true
        XCTAssertTrue(vm.isValidForm(shouldApprove: tx.isApproveRequired))
    }

    func testPreparePlaceableOrderRejectsUnsupportedExpiryViaValidation() async {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.marketPriceRef = 16  // positive routability proof
        // Two minutes: well under the 10-minute floor the app imposes.
        vm.draft.expiryBlocks = THORChainConstants.blocks(forMinutes: 2)

        XCTAssertNil(vm.preparePlaceableOrder())
        guard case .invalidInputs(let errors)? = vm.placeOrderError else {
            return XCTFail("Expected .invalidInputs, got \(String(describing: vm.placeOrderError))")
        }
        XCTAssertTrue(errors.contains(.expiryOutOfRange(
            blocks: THORChainConstants.blocks(forMinutes: 2),
            minBlocks: THORChainConstants.minLimitSwapAgeBlocks,
            maxBlocks: vm.maxExpiryBlocks
        )))
    }

    func testPreparePlaceableOrderReturnsNilSilentlyWhenAmountIsZero() {
        let vm = makeViewModel(sourceAmount: 0)
        vm.draft.targetPrice = 16

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertNil(vm.placeOrderError, "A not-ready draft returns nil without raising a user-facing error")
    }

    // MARK: - never a dead tap (memo/dest prerequisites)

    func testPreparePlaceableOrderRaisesPairNotPlaceableWhenTargetUnencodable() async {
        // A target asset with no THORChain memo encoding must surface an alert,
        // not silently return nil (the dead-tap bug).
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.draft.toAsset = LimitSwapAsset(
            chain: .solana, ticker: "SOL", decimals: 9,
            contractAddress: "", isNativeToken: true
        )

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertEqual(vm.placeOrderError, .pairNotPlaceable)
    }

    func testPreparePlaceableOrderRaisesPairNotPlaceableWhenNoDestinationAddress() async {
        // The vault holds no coin on the target chain → destinationAddress() nil.
        vault.coins.removeAll(where: { $0.chain == .ethereum })
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertEqual(vm.placeOrderError, .pairNotPlaceable)
    }

    func testCanPlaceOrderBlockedWhenTargetAssetUnencodable() async {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.networkFeeEstimate = BigInt(4_200)
        vm.marketPriceRef = 16  // isolate the memoSymbol cause from the probe gate
        vm.draft.toAsset = LimitSwapAsset(
            chain: .solana, ticker: "SOL", decimals: 9,
            contractAddress: "", isNativeToken: true
        )
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()), "An unencodable target must disable the CTA")
    }

    func testCanPlaceOrderBlockedWhenNoDestinationAddress() async {
        vault.coins.removeAll(where: { $0.chain == .ethereum })
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.networkFeeEstimate = BigInt(4_200)
        vm.marketPriceRef = 16  // isolate the destination cause from the probe gate
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()), "No destination address must disable the CTA")
    }

    func testRuneToTcyIsPlaceable() async {
        // Regression for the RUNE→TCY dead tap: TCY now encodes to THOR.TCY, so a
        // RUNE→TCY draft assembles a placeable order instead of a silent no-op.
        vault.coins.append(Coin(
            asset: CoinMeta.make(chain: .thorChain, ticker: "TCY", decimals: 8, isNativeToken: false),
            address: "thor1tcydest000000000000000000000000000000",
            hexPublicKey: "tcy-pubkey"
        ))
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.fromAsset = LimitSwapAsset(
            chain: .thorChain, ticker: "RUNE", decimals: 8,
            contractAddress: "", isNativeToken: true
        )
        vm.draft.toAsset = LimitSwapAsset(
            chain: .thorChain, ticker: "TCY", decimals: 8,
            contractAddress: "tcy", isNativeToken: false
        )
        vm.draft.targetPrice = Decimal(string: "4.6")!
        vm.marketPriceRef = Decimal(string: "4.6")!  // positive routability proof

        guard let prepared = vm.preparePlaceableOrder() else {
            return XCTFail("RUNE→TCY should assemble a placeable order")
        }
        XCTAssertNil(vm.placeOrderError)
        XCTAssertEqual(prepared.record.sourceAsset, "THOR.RUNE")
        XCTAssertEqual(prepared.record.targetAsset, "THOR.TCY")
        XCTAssertTrue(prepared.memo.hasPrefix("=<:THOR.TCY:"))
    }

    func testPreparePlaceableOrderWiresReferredAffiliateFragment() async {
        // A vault with a referral code produces the referred affiliate fragment
        // `<code>/vi` — verified via the same helper the market path uses.
        // Use an ETH (non-UTXO, 250B cap) source so the referred memo isn't
        // rejected by the 80B UTXO cap.
        vault.referralCode = ReferralCode(code: "myref", vault: vault)
        let vm = makeViewModel(sourceAmount: BigInt("1000000000000000000"))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.fromAsset = LimitSwapAsset(
            chain: .ethereum, ticker: "ETH", decimals: 18,
            contractAddress: "ETH-contract", isNativeToken: true
        )
        vm.draft.toAsset = LimitSwapAsset(
            chain: .bitcoin, ticker: "BTC", decimals: 8,
            contractAddress: "BTC-contract", isNativeToken: true
        )
        vm.draft.targetPrice = Decimal(string: "0.0625")!
        vm.marketPriceRef = Decimal(string: "0.0625")!  // positive routability proof

        guard let prepared = vm.preparePlaceableOrder() else {
            return XCTFail("Expected a prepared order")
        }
        XCTAssertTrue(
            prepared.memo.hasSuffix(":myref/\(THORChainSwaps.affiliateFeeAddress):\(THORChainSwaps.referredUserFeeRateBp)/\(THORChainSwaps.referredAffiliateFeeRateBp)"),
            "Referred affiliate fragment must be wired; got: \(prepared.memo)"
        )
    }

    func testPreparePlaceableOrderMapsByteCapOverflowToMemoTooLong() async {
        // BTC (UTXO, 80B cap) source + a token target with a referred affiliate
        // overflows the 80-byte cap → user-facing .memoTooLong.
        vault.referralCode = ReferralCode(code: "myref", vault: vault)
        // Target the vault's ETH address via a token asset with a long contract.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.toAsset = LimitSwapAsset(
            chain: .ethereum, ticker: "USDC", decimals: 6,
            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", isNativeToken: false
        )
        vm.draft.targetPrice = Decimal(string: "0.00002")!
        vm.marketPriceRef = Decimal(string: "0.00002")!  // positive routability proof

        XCTAssertNil(vm.preparePlaceableOrder())
        guard case .memoTooLong(let actual, let limit)? = vm.placeOrderError else {
            return XCTFail("Expected .memoTooLong, got \(String(describing: vm.placeOrderError))")
        }
        XCTAssertGreaterThan(actual, limit)
        XCTAssertEqual(limit, 80)
    }

    func testSelectPresetPctRoundsToEightDecimalsForRoundTripStability() {
        let vm = makeViewModel()
        vm.marketPriceRef = Decimal(string: "0.123456789")!  // 9-dp base
        vm.selectPresetPct(1)  // ×1.01 → more than 8 dp before rounding

        // The stored price must already be rounded to ≤ 8 dp so the text↔draft
        // round-trip (formatter caps at 8) is stable and doesn't clobber the preset.
        var rounded = Decimal()
        var value = vm.draft.targetPrice
        NSDecimalRound(&rounded, &value, 8, .plain)
        XCTAssertEqual(vm.draft.targetPrice, rounded, "Preset price must be pre-rounded to 8 dp")
    }

    // MARK: - Advanced Swap Queue mimir gate (fail-closed)

    func testPreparePlaceableOrderBlocksWhenQueueGateUnresolved() {
        // Fail-closed default: the mimir gate hasn't resolved (nil) yet, so a
        // fully valid draft must NOT be placeable.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.draft.targetPrice = 16
        vm.marketPriceRef = 16  // positive routability proof: isolate the queue gate
        XCTAssertNil(vm.advancedSwapQueueEnabled)

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertEqual(vm.placeOrderError, .advancedSwapQueueDisabled)
    }

    func testPreparePlaceableOrderBlocksWhenQueueGateDisabled() {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = false
        vm.draft.targetPrice = 16
        vm.marketPriceRef = 16  // positive routability proof: isolate the queue gate

        XCTAssertNil(vm.preparePlaceableOrder())
        XCTAssertEqual(vm.placeOrderError, .advancedSwapQueueDisabled)
    }

    func testRefreshAdvancedSwapQueueGateStoresEnabledResult() async {
        quoteService.advancedSwapQueueEnabledResult = true
        let vm = makeViewModel()

        await vm.refreshAdvancedSwapQueueGate()

        XCTAssertEqual(vm.advancedSwapQueueEnabled, true)
        XCTAssertTrue(vm.isAdvancedSwapQueueEnabled)
        XCTAssertEqual(quoteService.advancedSwapQueueCallCount, 1)
    }

    func testRefreshAdvancedSwapQueueGateStoresDisabledResult() async {
        quoteService.advancedSwapQueueEnabledResult = false
        let vm = makeViewModel()

        await vm.refreshAdvancedSwapQueueGate()

        XCTAssertEqual(vm.advancedSwapQueueEnabled, false)
        XCTAssertFalse(vm.isAdvancedSwapQueueEnabled)
    }

    // MARK: - canPlaceOrder (Place-Order gate incl. resolved network fee)

    func testCanPlaceOrderRequiresResolvedNetworkFee() async {
        // Fee-disclosure race: a fully valid draft must NOT be placeable until the
        // network-fee estimate resolves — otherwise the order is signed with a
        // blank fee the user never saw.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.marketPriceRef = 16  // positive routability proof (a resolved quote)
        vm.networkFeeEstimate = .zero
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()), "Must be blocked while the network fee is unresolved")

        vm.networkFeeEstimate = BigInt(4_200)
        XCTAssertTrue(vm.canPlaceOrder(sourceCoin: btcCoin()), "Placeable once amount, price, queue gate, fee and market ref are all resolved")
    }

    func testCanPlaceOrderRequiresSuccessfulMarketProbe() async {
        // Positive routability proof: without a resolved market reference (the
        // probe hasn't succeeded → the pair isn't proven routable) the CTA stays
        // disabled, closing the pre-probe window for a poolless pair.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.networkFeeEstimate = BigInt(4_200)
        vm.marketPriceRef = nil
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()), "Not placeable until the market probe proves the pair routable")

        vm.marketPriceRef = 16
        XCTAssertTrue(vm.canPlaceOrder(sourceCoin: btcCoin()))
    }

    func testCanPlaceOrderFalseWhenQueueDisabled() {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = false
        vm.draft.targetPrice = 16
        vm.networkFeeEstimate = BigInt(4_200)
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()))
    }

    func testCanPlaceOrderFalseWhenAmountOrPriceMissing() async {
        let vm = makeViewModel(sourceAmount: 0)
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.networkFeeEstimate = BigInt(4_200)
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()), "Zero amount is not placeable")

        vm.amountChanged(BigInt(100_000_000))
        vm.networkFeeEstimate = BigInt(4_200)  // amountChanged clears it; restore
        vm.draft.targetPrice = 0
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()), "Zero price is not placeable")
    }

    // MARK: - balance gate (the sell amount must be affordable, on THIS screen)

    func testCanPlaceOrderBlockedWhenAmountExceedsBalance() async {
        // The whole point of the gate: an order for more than the vault holds
        // must be refused on the FORM, not one screen later at Verify.
        let btc = btcCoin()
        btc.rawBalance = "100000000"  // 1 BTC
        let vm = await makeReadyToPlace(sourceAmount: BigInt(200_000_000))  // 2 BTC

        XCTAssertEqual(vm.balanceState(sourceCoin: btc), .insufficientFunds(sourceTicker: "BTC"))
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btc), "An over-balance amount must disable Place Order")

        // Both directions, so deleting the term fails this test either way.
        vm.amountChanged(BigInt(50_000_000))  // 0.5 BTC
        vm.networkFeeEstimate = BigInt(4_200)  // amountChanged clears it; restore
        XCTAssertEqual(vm.balanceState(sourceCoin: btc), .sufficient)
        XCTAssertTrue(vm.canPlaceOrder(sourceCoin: btc), "An affordable amount must re-enable Place Order")
    }

    func testAmountThatFitsButLeavesNothingForGasIsReportedAsGasNotFunds() async {
        // Market parity: the source coin pays its own gas, the amount alone fits,
        // so this is a GAS problem. Collapsing the two into one message — or
        // calling it insufficient funds — is the failure this pins.
        let btc = btcCoin()
        btc.rawBalance = "100000000"  // exactly 1 BTC
        let vm = await makeReadyToPlace(sourceAmount: BigInt(100_000_000))  // exactly 1 BTC
        vm.networkFeeEstimate = BigInt(10_000)

        XCTAssertEqual(vm.balanceState(sourceCoin: btc), .insufficientGas(feeTicker: "BTC"))
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btc))
    }

    func testNoGasErrorIsShownWhileTheFeeEstimateIsInFlight() async {
        // `networkFeeEstimate` is dropped to 0 on every input change. A gas
        // verdict is not knowable in that window, so none is shown — the form
        // must never display a gas error it would have to withdraw a frame later.
        let btc = btcCoin()
        btc.rawBalance = "100000000"
        let vm = await makeReadyToPlace(sourceAmount: BigInt(100_000_000))
        vm.networkFeeEstimate = .zero

        let inFlight = vm.balanceState(sourceCoin: btc)
        XCTAssertEqual(inFlight, .indeterminate)
        XCTAssertNil(inFlight.noticeMessage, "No notice may be rendered from an unresolved fee")
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btc), "Placement stays blocked until the fee resolves")

        // …and the moment the estimate lands, the real verdict appears — and it
        // is the ONLY term still blocking the CTA, so this pins the wiring too.
        vm.networkFeeEstimate = BigInt(10_000)
        XCTAssertEqual(vm.balanceState(sourceCoin: btc), .insufficientGas(feeTicker: "BTC"))
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btc))
    }

    func testInsufficientFundsIsStillReportedWhileTheFeeEstimateIsInFlight() async {
        // The funds question is fee-independent, so suppressing it during the
        // in-flight window would withhold an answer that cannot change.
        let btc = btcCoin()
        btc.rawBalance = "100000000"  // 1 BTC
        let vm = await makeReadyToPlace(sourceAmount: BigInt(200_000_000))  // 2 BTC
        vm.networkFeeEstimate = .zero

        let state = vm.balanceState(sourceCoin: btc)
        XCTAssertEqual(state, .insufficientFunds(sourceTicker: "BTC"))
        XCTAssertNotNil(state.noticeMessage)
    }

    func testErc20SourceJudgesGasAgainstTheNativeSiblingNotTheToken() async {
        // Gas is paid in the chain's NATIVE coin: an ERC20 source pays ETH. The
        // fee is in wei, so reading it against the token's 6 decimals would make
        // it look like ~1e9 tokens and report a false `insufficientGas` even with
        // a funded ETH sibling — the exact bug `SwapCryptoLogic.feeCoin` exists
        // to prevent. The second assertion is what catches that.
        let usdc = Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false),
            address: "0xethdestaddress00000000000000000000000000",
            hexPublicKey: "usdc-pubkey"
        )
        usdc.rawBalance = "1000000000"  // 1,000 USDC — the amount itself is covered
        vault.coins.append(usdc)
        let eth = ethCoin()
        eth.rawBalance = "0"  // no gas at all

        let vm = await makeReadyToPlace(sourceAmount: BigInt(100_000_000), fromAsset: LimitSwapAsset(coin: usdc))
        vm.networkFeeEstimate = BigInt(1_050_000_000_000_000)  // 0.00105 ETH in wei

        XCTAssertEqual(vm.balanceState(sourceCoin: usdc), .insufficientGas(feeTicker: "ETH"))
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: usdc))

        eth.rawBalance = "1000000000000000000"  // 1 ETH
        XCTAssertEqual(
            vm.balanceState(sourceCoin: usdc),
            .sufficient,
            "A wei fee must be judged in ETH's 18 decimals, not the token's 6"
        )
        // Funding the sibling is the ONLY thing that changed, so the CTA coming
        // back proves the split-fee-coin path is wired through `canPlaceOrder`
        // and not merely classified correctly in isolation.
        XCTAssertTrue(vm.canPlaceOrder(sourceCoin: usdc))
    }

    func testBalanceStateAgreesWithTheMarketSwapRuleForTheSameInput() async {
        // Anti-drift: the limit form must not grow a second affordability rule.
        // Same coins, same amount, same fee ⇒ same verdict as the market tab.
        let btc = btcCoin()
        btc.rawBalance = "100000000"  // 1 BTC
        let vm = await makeReadyToPlace(sourceAmount: BigInt(99_999_000))  // 0.99999 BTC
        vm.networkFeeEstimate = BigInt(10_000)

        let marketVerdict = SwapCryptoLogic.balanceError(
            fromCoin: btc,
            feeCoin: btc,
            fromAmount: "0.99999",
            fee: BigInt(10_000)
        )
        XCTAssertEqual(marketVerdict, .insufficientGas)
        XCTAssertEqual(vm.balanceState(sourceCoin: btc), .insufficientGas(feeTicker: "BTC"))
        // Every other `canPlaceOrder` term is satisfied here, so the disabled CTA
        // can only come from the shared rule's verdict.
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btc))
    }

    func testBalanceStateIsIndeterminateWhenTheCoinIsNotTheDraftSource() async {
        // SwiftUI can render one frame with a newly-picked coin and the previous
        // draft asset. Judging a BTC amount against an ETH balance for that frame
        // would flash a bogus row, so the verdict is withheld and placement fails
        // closed.
        let vm = await makeReadyToPlace(sourceAmount: BigInt(100_000_000))  // draft source is BTC

        XCTAssertEqual(vm.balanceState(sourceCoin: ethCoin()), .indeterminate)
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: ethCoin()))
    }

    func testBalanceNoticesNameTheAssetAndDistinguishFundsFromGas() {
        let funds = LimitSwapBalanceState.insufficientFunds(sourceTicker: "BTC").noticeMessage
        let gas = LimitSwapBalanceState.insufficientGas(feeTicker: "ETH").noticeMessage

        XCTAssertEqual(funds?.contains("BTC"), true, "The funds notice must name the source asset")
        XCTAssertEqual(gas?.contains("ETH"), true, "The gas notice must name the fee asset")
        XCTAssertNotEqual(funds, gas, "The two cases must not collapse into one message")

        XCTAssertNil(LimitSwapBalanceState.sufficient.noticeMessage)
        XCTAssertNil(LimitSwapBalanceState.indeterminate.noticeMessage)
        XCTAssertFalse(LimitSwapBalanceState.sufficient.blocksPlacement)
        XCTAssertTrue(LimitSwapBalanceState.indeterminate.blocksPlacement, "Unknown must fail closed")
    }

    // MARK: - pair routability gate (poolless pairs must not be placeable)

    func testRefreshMarketPricePoolErrorMarksPairUnroutable() async {
        // A poolless pair (e.g. RUNE→VULT) makes THORChain's quote endpoint
        // return {code,message} → ThorchainSwapError. That must mark the pair
        // unplaceable so the CTA disables and the inline row shows.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        quoteService.marketPriceResult = .failure(
            ThorchainSwapError(code: 3, message: "pool does not exist: invalid request")
        )

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.pairUnroutableReason, .noRoute)
        XCTAssertNotNil(vm.marketPriceError)
    }

    func testRefreshMarketPriceSuccessClearsUnroutableReason() async {
        // A later successful quote proves the pair routable and clears the block.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.pairUnroutableReason = .noRoute
        quoteService.marketPriceResult = .success(Decimal(string: "16.5")!)

        await vm.refreshMarketPrice()

        XCTAssertNil(vm.pairUnroutableReason)
        XCTAssertEqual(vm.marketPriceRef, Decimal(string: "16.5")!)
    }

    func testRefreshMarketPriceTransientErrorDoesNotMarkPairUnroutable() async {
        // A non-THORChain (transient network) error must NOT flag the pair
        // unroutable — only a server-side no-pool refusal does.
        struct UpstreamError: Error {}
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        quoteService.marketPriceResult = .failure(UpstreamError())

        await vm.refreshMarketPrice()

        XCTAssertNil(vm.pairUnroutableReason, "A transient error must not flag the pair unroutable")
        XCTAssertNotNil(vm.marketPriceError)
    }

    func testRefreshMarketPriceNonPoolServerErrorDoesNotMarkPairUnroutable() async {
        // ThorchainSwapError is THORNode's generic error envelope — a non-pool
        // failure (e.g. a dust/amount rejection) must NOT be mislabeled as a
        // routing failure. Only the "...pool does not exist..." message does.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        quoteService.marketPriceResult = .failure(
            ThorchainSwapError(code: 3, message: "swap amount is too small to cover the outbound fee")
        )

        await vm.refreshMarketPrice()

        XCTAssertNil(vm.pairUnroutableReason, "A non-pool server error must not flag the pair unroutable")
        XCTAssertNotNil(vm.marketPriceError)
    }

    func testRefreshMarketPriceUnsupportedAssetMarksPairUnroutable() async {
        // An asset with no memo-asset encoding (unroutable chain) can't be placed.
        let vm = makeViewModel()
        vm.draft.toAsset = LimitSwapAsset(
            chain: .solana, ticker: "SOL", decimals: 9,
            contractAddress: "", isNativeToken: true
        )

        await vm.refreshMarketPrice()

        XCTAssertEqual(vm.pairUnroutableReason, .unsupportedAsset)
    }

    func testCanPlaceOrderBlockedWhenPairUnroutable() async {
        // Defence-in-depth: even with a (stale) market reference present, a pair
        // the probe flagged unroutable must not be placeable.
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.networkFeeEstimate = BigInt(4_200)
        vm.marketPriceRef = 16
        XCTAssertTrue(vm.canPlaceOrder(sourceCoin: btcCoin()))

        vm.pairUnroutableReason = .noRoute
        XCTAssertFalse(vm.canPlaceOrder(sourceCoin: btcCoin()), "A pair THORChain can't route must not be placeable")

        vm.pairUnroutableReason = nil
        XCTAssertTrue(vm.canPlaceOrder(sourceCoin: btcCoin()))
    }

    func testSelectFromAssetClearsUnroutableReason() {
        let vm = makeViewModel()
        vm.pairUnroutableReason = .noRoute
        vm.selectFromAsset(LimitSwapAsset(
            chain: .litecoin, ticker: "LTC", decimals: 8,
            contractAddress: "", isNativeToken: true
        ))
        XCTAssertNil(vm.pairUnroutableReason)
    }

    func testSelectToAssetClearsUnroutableReason() {
        let vm = makeViewModel()
        vm.pairUnroutableReason = .noRoute
        vm.selectToAsset(LimitSwapAsset(
            chain: .thorChain, ticker: "RUNE", decimals: 8,
            contractAddress: "", isNativeToken: true
        ))
        XCTAssertNil(vm.pairUnroutableReason)
    }

    // MARK: - expectedBuyAmount (memoized)

    func testExpectedBuyAmountMatchesComputeAndUpdatesWithInputs() {
        let vm = makeViewModel(sourceAmount: BigInt(100_000_000))  // 1 BTC (8 dec)
        vm.draft.targetPrice = 16
        let expected = limitOrderExpectedOutput(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(vm.expectedBuyAmount, expected)
        // Repeat read (cache hit) returns the same value.
        XCTAssertEqual(vm.expectedBuyAmount, expected)

        // Changing a keyed input invalidates the cache and recomputes.
        vm.draft.targetPrice = 32
        let expected2 = limitOrderExpectedOutput(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: 32)
        XCTAssertEqual(vm.expectedBuyAmount, expected2)
        XCTAssertNotEqual(expected2, expected)

        vm.amountChanged(BigInt(50_000_000))
        XCTAssertEqual(
            vm.expectedBuyAmount,
            limitOrderExpectedOutput(sourceAmount: BigInt(50_000_000), sourceDecimals: 8, targetPrice: 32)
        )
    }

    // MARK: - fixtures

    private func makeViewModel(
        sourceAmount: BigInt = 0,
        initialDisplayUnit: PriceDisplayUnit = .asset
    ) -> LimitSwapFormViewModel {
        makeViewModel(interactor: interactor, sourceAmount: sourceAmount, initialDisplayUnit: initialDisplayUnit)
    }

    private func makeViewModel(
        interactor: LimitSwapInteractor,
        sourceAmount: BigInt = 0,
        initialDisplayUnit: PriceDisplayUnit = .asset
    ) -> LimitSwapFormViewModel {
        let draft = LimitSwapDraft(
            fromAsset: btcAsset(),
            toAsset: ethAsset(),
            sourceAmount: sourceAmount,
            displayUnit: initialDisplayUnit
        )
        return LimitSwapFormViewModel(
            initialDraft: draft,
            vault: vault,
            interactor: interactor
        )
    }

    /// A draft with every NON-balance `canPlaceOrder` term already satisfied, so
    /// a `false` verdict in the balance tests can only come from the balance gate.
    ///
    /// That includes the resolved TTL ceiling: `canPlaceOrder` requires it so an
    /// order can never be signed against the seeded default while the live
    /// `StreamingLimitSwapMaxAge` is still in flight.
    private func makeReadyToPlace(
        sourceAmount: BigInt,
        fromAsset: LimitSwapAsset? = nil
    ) async -> LimitSwapFormViewModel {
        let draft = LimitSwapDraft(
            fromAsset: fromAsset ?? btcAsset(),
            toAsset: ethAsset(),
            sourceAmount: sourceAmount
        )
        let vm = LimitSwapFormViewModel(
            initialDraft: draft,
            vault: vault,
            interactor: interactor
        )
        vm.advancedSwapQueueEnabled = true
        await vm.refreshMaxExpiry()  // same screen task resolves the TTL ceiling
        vm.draft.targetPrice = 16
        vm.marketPriceRef = 16
        vm.networkFeeEstimate = BigInt(4_200)
        return vm
    }

    /// The vault's BTC / ETH coins (installed in `setUp`) — for VM methods that
    /// take concrete source/target `Coin`s (e.g. the network-fee estimate).
    private func btcCoin() -> Coin {
        vault.coins.first { $0.chain == .bitcoin }!
    }

    private func ethCoin() -> Coin {
        vault.coins.first { $0.chain == .ethereum }!
    }

    private func btcAsset() -> LimitSwapAsset {
        LimitSwapAsset(chain: .bitcoin, ticker: "BTC", decimals: 8, contractAddress: "BTC-contract", isNativeToken: true)
    }

    private func ethAsset() -> LimitSwapAsset {
        LimitSwapAsset(chain: .ethereum, ticker: "ETH", decimals: 18, contractAddress: "ETH-contract", isNativeToken: true)
    }
    // MARK: - The pair chart cannot outlive its pair

    func testSwitchingTheTargetAssetDropsTheChartImmediately() {
        // A drag on a chart priced in the OLD pair's units writes that value
        // into the NEW pair's target price, and — being a deliberate edit — also
        // suppresses the auto-seed that would have corrected it. BTC/ETH's ~30
        // becoming the target for BTC/USDC at ~118,000 places an order that
        // fills instantly at a catastrophic loss. The chart must be gone before
        // the debounced refresh has even started.
        let vm = makeViewModel()
        vm.pairChart = MarketChart(points: (0..<40).map {
            MarketChartPoint(date: Date(timeIntervalSince1970: Double($0) * 60), price: 30)
        })

        vm.selectToAsset(
            LimitSwapAsset(
                chain: .ethereum, ticker: "USDC", decimals: 6,
                contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                isNativeToken: false, priceProviderId: "usd-coin"
            )
        )

        XCTAssertNil(vm.pairChart)
        XCTAssertFalse(vm.isLoadingPairChart)
    }

    func testSwitchingTheSourceAssetDropsTheChartImmediately() {
        let vm = makeViewModel()
        vm.pairChart = MarketChart(points: (0..<40).map {
            MarketChartPoint(date: Date(timeIntervalSince1970: Double($0) * 60), price: 30)
        })

        vm.selectFromAsset(
            LimitSwapAsset(
                chain: .thorChain, ticker: "RUNE", decimals: 8,
                contractAddress: "", isNativeToken: true, priceProviderId: "thorchain"
            )
        )

        XCTAssertNil(vm.pairChart)
    }

}

private struct UntestedError: Error {}
