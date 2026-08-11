//
//  LimitMathTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

final class LimitMathTests: XCTestCase {

    // MARK: - computeLim — integer prices

    func testComputeLimForOneBtcAt16PerBtc() throws {
        let lim = try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(lim, BigInt(1_600_000_000))
    }

    func testComputeLimForHalfBtcAt16PerBtc() throws {
        let lim = try computeLim(sourceAmount: BigInt(50_000_000), sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(lim, BigInt(800_000_000))
    }

    func testComputeLimForOneBtcAt6000PerBtc() throws {
        let lim = try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: 6000)
        XCTAssertEqual(lim, BigInt(600_000_000_000))
    }

    // MARK: - computeLim — fractional prices

    func testComputeLimForOneEthAt00625PerEth() throws {
        let lim = try computeLim(
            sourceAmount: BigInt("1000000000000000000"),
            sourceDecimals: 18,
            targetPrice: Decimal(string: "0.0625")!
        )
        XCTAssertEqual(lim, BigInt(6_250_000))
    }

    func testComputeLimForFiftyKUsdtAt000001PerUsdt() throws {
        let lim = try computeLim(
            sourceAmount: BigInt(50_000_000_000),
            sourceDecimals: 6,
            targetPrice: Decimal(string: "0.00001")!
        )
        XCTAssertEqual(lim, BigInt(50_000_000))
    }

    // MARK: - computeLim — edge cases

    func testComputeLimForVerySmallPriceProducesOne() throws {
        // 1 BTC at 0.00000001 target/source → 0.00000001 target → LIM = 1 (1e8 fixed-point)
        let lim = try computeLim(
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetPrice: Decimal(string: "0.00000001")!
        )
        XCTAssertEqual(lim, BigInt(1))
    }

    func testComputeLimForVeryLargePrice() throws {
        // 1 BTC at 1_000_000 target/source → 1_000_000 target → LIM = 1e14
        let lim = try computeLim(
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetPrice: 1_000_000
        )
        XCTAssertEqual(lim, BigInt("100000000000000"))
    }

    func testComputeLimTruncatesPriceBeyondEightDecimalPlaces() throws {
        // targetPrice = 16.123456789 (9 dp); should truncate to 16.12345678 in 1e8 fixed-point
        // → LIM = 1_612_345_678 (not 1_612_345_678.9, not 0)
        let lim = try computeLim(
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetPrice: Decimal(string: "16.123456789")!
        )
        XCTAssertEqual(lim, BigInt(1_612_345_678))
    }

    func testComputeLimZeroSourceAmountReturnsZero() throws {
        let lim = try computeLim(sourceAmount: 0, sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(lim, BigInt(0))
    }

    // MARK: - computeLim — overflow MUST fail loud (fund-safety)

    func testComputeLimOverflowingTargetPriceThrowsInsteadOfYieldingZero() {
        // A `targetPrice` near `Decimal.greatestFiniteMagnitude` (~1e127)
        // overflows when scaled by 1e8. The old code did `BigInt("NaN") ?? 0`,
        // silently emitting LIM=0 — which THORChain reads as "fill at ANY
        // price", the OPPOSITE of a limit order. We must THROW, never return 0.
        let huge = Decimal.greatestFiniteMagnitude
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: huge)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .targetPriceOverflow)
        }
    }

    func testComputeLimOverflowNeverSilentlyProducesZero() throws {
        // Belt-and-suspenders: assert no overflow path returns 0. If it didn't
        // throw, it must be a genuine non-zero value.
        let huge = Decimal.greatestFiniteMagnitude
        do {
            let lim = try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: huge)
            XCTAssertNotEqual(lim, BigInt(0), "Overflow must never silently yield LIM=0")
        } catch {
            XCTAssertEqual(error as? LimitSwapMemoError, .targetPriceOverflow)
        }
    }

    // MARK: - computeLim — underflow MUST fail loud (fund-safety)

    func testComputeLimUnderflowingToZeroWithPositiveInputsThrows() {
        // 1 wei source (18 decimals) at price 1 scales to LIM = 1e8 / 1e18, which
        // truncates to 0. Both inputs are positive, so a `LIM=0` memo ("fill at
        // ANY price") would be a fund-safety hazard — must THROW, not return 0.
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(1), sourceDecimals: 18, targetPrice: 1)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    func testComputeLimUnderflowFromTinyPriceThrows() {
        // Dust output from a very low target price against a high-decimal source.
        XCTAssertThrowsError(
            try computeLim(
                sourceAmount: BigInt(1),
                sourceDecimals: 18,
                targetPrice: Decimal(string: "0.0001")!
            )
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    func testComputeLimStillReturnsZeroForZeroSourceAmount() throws {
        // A zero source amount is a separate precondition (rejected upstream by
        // validation), not the positive-input underflow the guard targets — it
        // must keep returning 0 without throwing.
        let lim = try computeLim(sourceAmount: 0, sourceDecimals: 18, targetPrice: 1)
        XCTAssertEqual(lim, BigInt(0))
    }

    func testComputeLimZeroTargetPriceWithPositiveSourceThrows() {
        // Defense-in-depth: a zero target price against a POSITIVE source yields
        // LIM = 0 ("fill at ANY price"). The guard must fire regardless of the
        // target price's sign, so this throws rather than emitting a price-blind
        // order. (validateLimitSwapInputs also rejects a non-positive price.)
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: 0)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    // MARK: - computeLim — negative inputs MUST fail loud (fund-safety)

    func testComputeLimNegativeSourceAmountThrows() {
        // A negative source amount would produce a NEGATIVE LIM that slips past
        // the `lim <= 0` underflow guard (which requires both inputs positive).
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(-100_000_000), sourceDecimals: 8, targetPrice: 16)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    func testComputeLimNegativeTargetPriceThrows() {
        XCTAssertThrowsError(
            try computeLim(sourceAmount: BigInt(100_000_000), sourceDecimals: 8, targetPrice: -16)
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    func testComputeLimNegativeBothInputsThrows() {
        XCTAssertThrowsError(
            try computeLim(
                sourceAmount: BigInt(-100_000_000),
                sourceDecimals: 8,
                targetPrice: Decimal(string: "-0.5")!
            )
        ) { error in
            XCTAssertEqual(error as? LimitSwapMemoError, .limitAmountTooSmall)
        }
    }

    // MARK: - limitOrderExpectedOutput (Verify / Done display amount)

    func testLimitOrderExpectedOutputForOneBtcAt16() {
        let out = limitOrderExpectedOutput(
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetPrice: 16
        )
        XCTAssertEqual(out, Decimal(16))
    }

    func testLimitOrderExpectedOutputForFractionalPrice() {
        let out = limitOrderExpectedOutput(
            sourceAmount: BigInt("1000000000000000000"),
            sourceDecimals: 18,
            targetPrice: Decimal(string: "0.0625")!
        )
        XCTAssertEqual(out, Decimal(string: "0.0625")!)
    }

    func testLimitOrderExpectedOutputForZeroSourceIsZero() {
        let out = limitOrderExpectedOutput(sourceAmount: 0, sourceDecimals: 8, targetPrice: 16)
        XCTAssertEqual(out, Decimal(0))
    }

    // MARK: - marketProbeAmount (pre-input market-price probe)

    func testMarketProbeUsesUserAmountWhenPositive() {
        // Once the user has typed an amount it is used verbatim regardless of price.
        let probe = marketProbeAmount(
            sourceAmount: BigInt(123_456),
            sourceDecimals: 8,
            sourceFiatPricePerUnit: Decimal(string: "1.4")!
        )
        XCTAssertEqual(probe, BigInt(123_456))
    }

    func testMarketProbeSizesToNotionalForCheapSource() {
        // 0 amount, $2/unit, $100 notional → 50 units × 1e8 = 5_000_000_000.
        let probe = marketProbeAmount(
            sourceAmount: 0,
            sourceDecimals: 8,
            sourceFiatPricePerUnit: 2
        )
        XCTAssertEqual(probe, BigInt(5_000_000_000))
    }

    func testMarketProbeCheapSourceExceedsOneWholeUnit() {
        // A cheap source (RUNE ≈ $1.4) must probe with MORE than 1 whole unit —
        // this is exactly the case the old `max(amount, 1 unit)` seed got wrong.
        let oneUnit = BigInt(10).power(8)
        let probe = marketProbeAmount(
            sourceAmount: 0,
            sourceDecimals: 8,
            sourceFiatPricePerUnit: Decimal(string: "1.4")!
        )
        XCTAssertGreaterThan(probe, oneUnit)
    }

    func testMarketProbeExpensiveSourceIsFractionOfOneUnit() {
        // 0 amount, $50_000/unit (BTC-ish), $100 notional → 0.002 BTC = 200_000 sats,
        // i.e. LESS than one whole unit. The notional probe never over-sizes to a
        // whole expensive coin.
        let probe = marketProbeAmount(
            sourceAmount: 0,
            sourceDecimals: 8,
            sourceFiatPricePerUnit: 50_000
        )
        XCTAssertEqual(probe, BigInt(200_000))
    }

    func testMarketProbeHighDecimalSource() {
        // 0 amount, $50/unit, $100 notional, 18-decimal source → 2 units × 1e18.
        let probe = marketProbeAmount(
            sourceAmount: 0,
            sourceDecimals: 18,
            sourceFiatPricePerUnit: 50
        )
        XCTAssertEqual(probe, BigInt("2000000000000000000"))
    }

    func testMarketProbeFallsBackToOneUnitWithoutRate() {
        // No USD rate (0) → fall back to the prior 1-unit (`10^decimals`) seed.
        let probe = marketProbeAmount(
            sourceAmount: 0,
            sourceDecimals: 8,
            sourceFiatPricePerUnit: 0
        )
        XCTAssertEqual(probe, BigInt(10).power(8))
    }

    func testMarketProbeCustomNotional() {
        // Explicit notional is honoured: $10 at $2/unit → 5 units × 1e8.
        let probe = marketProbeAmount(
            sourceAmount: 0,
            sourceDecimals: 8,
            sourceFiatPricePerUnit: 2,
            notionalFiat: 10
        )
        XCTAssertEqual(probe, BigInt(500_000_000))
    }

    // MARK: - preferredLimitSourceChain (limit-entry default source)

    // The BTC/ETH preference below applies to the NO-INTENT default only — an
    // inherited alphabetical market default (`isSourceExplicit: false`). The
    // explicit-intent contract is covered in the section after this one.

    func testPreferredLimitSourcePrefersBTCWhenHeld() {
        // Market default lands on RUNE; BTC is held and isn't the target → BTC.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .thorChain,
            isSourceExplicit: false,
            targetChain: .ethereum,
            availableNativeChains: [.bitcoin, .thorChain]
        )
        XCTAssertEqual(chain, .bitcoin)
    }

    func testPreferredLimitSourceSkipsTargetChainAndFallsToETH() {
        // Default RUNE→BTC: BTC is the target, so skip it and pick ETH → ETH→BTC.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .thorChain,
            isSourceExplicit: false,
            targetChain: .bitcoin,
            availableNativeChains: [.bitcoin, .ethereum, .thorChain]
        )
        XCTAssertEqual(chain, .ethereum)
    }

    func testPreferredLimitSourcePrefersBTCOverETHWhenBothHeld() {
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .thorChain,
            isSourceExplicit: false,
            targetChain: .thorChain,
            availableNativeChains: [.bitcoin, .ethereum]
        )
        XCTAssertEqual(chain, .bitcoin)
    }

    func testPreferredLimitSourceFallsBackToMarketDefaultWhenNeitherHeld() {
        // Neither BTC nor ETH held (BTC is the target and not preferable anyway) →
        // keep the market default rather than inventing an unheld source.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .litecoin,
            isSourceExplicit: false,
            targetChain: .bitcoin,
            availableNativeChains: [.litecoin, .thorChain]
        )
        XCTAssertEqual(chain, .litecoin)
    }

    func testPreferredLimitSourceKeepsMarketDefaultWhenItIsAlreadyBTC() {
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .bitcoin,
            isSourceExplicit: false,
            targetChain: .ethereum,
            availableNativeChains: [.bitcoin]
        )
        XCTAssertEqual(chain, .bitcoin)
    }

    func testPreferredLimitSourceAvoidsSelfPairWhenMarketDefaultEqualsTarget() {
        // Same-chain market default (e.g. ETH→USDC both on Ethereum) with no
        // BTC/ETH-vs-target preferred candidate must NOT seed a same-chain
        // self-pair — pick another held native chain instead.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .ethereum,
            isSourceExplicit: false,
            targetChain: .ethereum,
            availableNativeChains: [.ethereum, .thorChain]
        )
        XCTAssertNotEqual(chain, .ethereum)
        XCTAssertEqual(chain, .thorChain)
    }

    func testPreferredLimitSourceReturnsMarketDefaultWhenOnlyTargetChainHeld() {
        // Degenerate: the vault holds only the target chain, so a self-pair is
        // unavoidable — return the market default rather than an unheld chain.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .ethereum,
            isSourceExplicit: false,
            targetChain: .ethereum,
            availableNativeChains: [.ethereum]
        )
        XCTAssertEqual(chain, .ethereum)
    }

    func testPreferredLimitSourceSkipsUnroutableAlternate() {
        // Same-chain market default with only an UNROUTABLE native alternate
        // (SOL) must NOT seed the unroutable source (the place gate would reject
        // it) — fall back to the market default instead.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .ethereum,
            isSourceExplicit: false,
            targetChain: .ethereum,
            availableNativeChains: [.ethereum, .solana]
        )
        XCTAssertEqual(chain, .ethereum)
    }

    func testPreferredLimitSourceSkipsUnroutableMarketDefault() {
        // An unroutable market default (SOL) with a held routable alternate (LTC)
        // must pick the routable alternate rather than seed the unroutable default.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .solana,
            isSourceExplicit: false,
            targetChain: .ethereum,
            availableNativeChains: [.solana, .litecoin]
        )
        XCTAssertEqual(chain, .litecoin)
    }

    // MARK: - preferredLimitSourceChain (explicit user intent)

    func testPreferredLimitSourceHonorsExplicitThorchainSource() {
        // Entering the swap from THORChain chain detail is real user intent: the
        // Limit tab must keep RUNE as the source instead of silently switching to
        // BTC, even though BTC is held and would win the no-intent preference.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .thorChain,
            isSourceExplicit: true,
            targetChain: .bitcoin,
            availableNativeChains: [.bitcoin, .ethereum, .thorChain]
        )
        XCTAssertEqual(chain, .thorChain)
    }

    func testPreferredLimitSourceHonorsExplicitNonPreferredSource() {
        // Any explicitly chosen routable source is honored, not just THORChain —
        // the BTC/ETH preference must not override an intentional LTC entry.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .litecoin,
            isSourceExplicit: true,
            targetChain: .ethereum,
            availableNativeChains: [.bitcoin, .ethereum, .litecoin]
        )
        XCTAssertEqual(chain, .litecoin)
    }

    func testPreferredLimitSourceFallsBackWhenExplicitSourceIsUnroutable() {
        // Explicit but NOT THORChain-routable (SOL): honoring it would seed an
        // unplaceable order, so fall back to the BTC/ETH preference.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .solana,
            isSourceExplicit: true,
            targetChain: .ethereum,
            availableNativeChains: [.bitcoin, .ethereum, .solana]
        )
        XCTAssertEqual(chain, .bitcoin)
    }

    func testPreferredLimitSourceFallsBackWhenExplicitSourceIsUnroutableTON() {
        // Same rule for a second unroutable chain, with no BTC/ETH held → the
        // routable alternate (LTC) wins over the unplaceable explicit source.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .ton,
            isSourceExplicit: true,
            targetChain: .ethereum,
            availableNativeChains: [.ton, .litecoin]
        )
        XCTAssertEqual(chain, .litecoin)
    }

    func testPreferredLimitSourceAvoidsSelfPairWhenExplicitSourceEqualsTarget() {
        // Explicit ETH source with an Ethereum target (e.g. the buy-VULT entry:
        // explicit ETH → VULT on Ethereum) is a self-pair — intent can't make it
        // routable, so fall through to a held routable source instead.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .ethereum,
            isSourceExplicit: true,
            targetChain: .ethereum,
            availableNativeChains: [.bitcoin, .ethereum]
        )
        XCTAssertNotEqual(chain, .ethereum)
        XCTAssertEqual(chain, .bitcoin)
    }

    func testPreferredLimitSourceExplicitSelfPairFallsBackToMarketDefaultWhenNothingElseHeld() {
        // Degenerate: explicit source == target and no other routable native is
        // held — a self-pair is unavoidable, so keep the concrete market default.
        let chain = preferredLimitSourceChain(
            marketDefaultChain: .ethereum,
            isSourceExplicit: true,
            targetChain: .ethereum,
            availableNativeChains: [.ethereum]
        )
        XCTAssertEqual(chain, .ethereum)
    }

    // MARK: - isUserFieldEdit (mirrored-field feedback suppression)

    func testIsUserUsdPriceEditTreatsProgrammaticEchoAsNonEdit() {
        // The value the view just wrote programmatically must NOT be treated as a
        // user edit — otherwise a preset/rate/mode redraw would round the
        // canonical price through the 2-dp USD display.
        XCTAssertFalse(isUserFieldEdit(newText: "2870", lastSyncedText: "2870"))
    }

    func testIsUserUsdPriceEditTreatsDifferentTextAsUserEdit() {
        XCTAssertTrue(isUserFieldEdit(newText: "3000", lastSyncedText: "2870"))
    }

    func testIsUserUsdPriceEditTreatsChangeWithNoPriorSyncAsUserEdit() {
        XCTAssertTrue(isUserFieldEdit(newText: "3000", lastSyncedText: nil))
    }

    // MARK: - computePresetPrice

    func testPresetPriceMarket() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: 0), 100)
    }

    func testPresetPricePlusOnePercent() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: 1), 101)
    }

    func testPresetPricePlusFivePercent() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: 5), 105)
    }

    func testPresetPricePlusTenPercent() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: 10), 110)
    }

    func testPresetPriceWithFractionalMarket() {
        // 0.0625 × 1.05 = 0.065625
        XCTAssertEqual(computePresetPrice(marketPrice: Decimal(string: "0.0625")!, pctAboveMarket: 5), Decimal(string: "0.065625")!)
    }

    func testPresetPriceWithFractionalPercent() {
        // The custom-offset sheet's reason for existing: 7.5% is not a preset.
        XCTAssertEqual(
            computePresetPrice(marketPrice: 200, pctAboveMarket: Decimal(string: "7.5")!),
            215
        )
    }

    func testPresetPriceWithNegativePercent() {
        XCTAssertEqual(computePresetPrice(marketPrice: 100, pctAboveMarket: -3), 97)
    }

    func testPresetPriceInvertsPctFromMarket() {
        // The sheet writes through one and the chip reads back through the other,
        // so the two must be exact inverses or the readout drifts from the control.
        let market = Decimal(string: "27.4218")!
        let pct = Decimal(string: "12.5")!
        let price = computePresetPrice(marketPrice: market, pctAboveMarket: pct)
        XCTAssertEqual(computePctFromMarket(targetPrice: price, marketPrice: market), pct)
    }

    // MARK: - Custom percent-offset stepper

    func testClampOffsetHoldsTheFloorAboveMinusOneHundred() {
        // -100% is a zero target price, and a zero LIM means "fill at ANY price".
        // The floor has to stay clear of it however long + is held.
        XCTAssertEqual(clampLimitPctOffset(-250), limitPctOffsetRange.lowerBound)
        XCTAssertGreaterThan(limitPctOffsetRange.lowerBound, -100)
    }

    func testClampOffsetHoldsTheCeiling() {
        XCTAssertEqual(clampLimitPctOffset(5_000), limitPctOffsetRange.upperBound)
    }

    func testClampOffsetLeavesAnInRangeValueAlone() {
        let pct = Decimal(string: "7.5")!
        XCTAssertEqual(clampLimitPctOffset(pct), pct)
    }

    func testOffsetSeedSnapsOntoTheStepperGrid() {
        // A chart drag leaves an arbitrary offset behind. Seeding it raw would
        // make the first + tap read +7.6512 — a control that appears not to know
        // its own step.
        XCTAssertEqual(limitPctOffsetSeed(from: Decimal(string: "7.5512")!), Decimal(string: "7.6")!)
        XCTAssertEqual(limitPctOffsetSeed(from: Decimal(string: "-2.04")!), Decimal(string: "-2.0")!)
    }

    func testOffsetSeedClampsBeforeSnapping() {
        XCTAssertEqual(limitPctOffsetSeed(from: 4_000), limitPctOffsetRange.upperBound)
    }

    func testOffsetSeedIsStableForAValueAlreadyOnTheGrid() {
        // Open, close, reopen must not walk the value.
        let seeded = limitPctOffsetSeed(from: Decimal(string: "7.5512")!)
        XCTAssertEqual(limitPctOffsetSeed(from: seeded), seeded)
    }

    func testSteppingStaysOnTheGrid() {
        // Ten taps of the finest step land exactly on the whole number, with no
        // binary-float dust — the display shows two decimals and would expose it.
        var pct = Decimal(string: "7.5")!
        for _ in 0..<10 {
            pct = clampLimitPctOffset(pct + limitPctOffsetStep)
        }
        XCTAssertEqual(pct, Decimal(string: "8.5")!)
    }

    func testHoldStepStartsAtTheTapIncrement() {
        // A hold that is only marginally longer than a tap must not overshoot.
        XCTAssertEqual(limitPctStep(forHeldSeconds: 0), limitPctOffsetStep)
        XCTAssertEqual(limitPctStep(forHeldSeconds: 0.9), limitPctOffsetStep)
    }

    func testHoldStepAcceleratesWithTheHold() {
        XCTAssertEqual(limitPctStep(forHeldSeconds: 1.5), Decimal(string: "0.5")!)
        XCTAssertEqual(limitPctStep(forHeldSeconds: 3), 1)
    }

    func testHoldStepIsMonotonic() {
        // The step may widen as a press is held but must never narrow — a stepper
        // that slowed down mid-hold would read as a stutter.
        var previous = Decimal(0)
        for tick in stride(from: 0.0, through: 5.0, by: 0.1) {
            let step = limitPctStep(forHeldSeconds: tick)
            XCTAssertGreaterThanOrEqual(step, previous, "step narrowed at \(tick)s")
            previous = step
        }
    }

    func testHoldCrossesTheFarAboveMarketThresholdInSeconds() {
        // The reason the step accelerates at all: from Market, a held + has to
        // reach the +20% where the far-above-market warning starts without the
        // user giving up. Replays the button's own schedule (0.4s before the
        // first repeat, then a tick every 0.08s).
        var pct = clampLimitPctOffset(limitPctStep(forHeldSeconds: 0))
        var held = 0.4
        while pct < 20, held < 10 {
            pct = clampLimitPctOffset(pct + limitPctStep(forHeldSeconds: held))
            held += 0.08
        }
        XCTAssertGreaterThanOrEqual(pct, 20)
        XCTAssertLessThan(held, 5, "a held + should cross +20% in a few seconds")
    }

    // MARK: - limitSourceAmount (Buy-driven entry)

    func testSourceAmountForTargetOutputIsTheInverseOfExpectedOutput() {
        // 0.25 BTC at 28.79289 ETH/BTC buys ~7.198 ETH; asking for that output
        // must come back to the same deposit.
        let price = Decimal(string: "28.79289")!
        let output = limitOrderExpectedOutput(
            sourceAmount: BigInt(25_000_000),
            sourceDecimals: 8,
            targetPrice: price
        )
        let source = limitSourceAmount(forTargetOutput: output, targetPrice: price, sourceDecimals: 8)
        XCTAssertEqual(source, BigInt(25_000_000))
    }

    func testSourceAmountTruncatesRatherThanRoundingUp() {
        // Rounding up would spend more of the balance than asked, purely to make
        // a screen figure come out exact. One smallest-unit short is the safe
        // direction: the re-derived output is what the order guarantees.
        let source = limitSourceAmount(
            forTargetOutput: Decimal(string: "0.000000015")!,
            targetPrice: 1,
            sourceDecimals: 8
        )
        XCTAssertEqual(source, BigInt(1), "1.5 smallest units must truncate to 1, not round to 2")
    }

    func testSourceAmountNeverOverstatesTheGuaranteedOutput() {
        // The invariant that makes truncation safe: re-deriving the output from
        // the truncated deposit must never exceed what was asked for.
        let price = Decimal(string: "3.7")!
        for requested in ["1", "10", "0.5", "123.456789"] {
            let output = Decimal(string: requested)!
            let source = limitSourceAmount(forTargetOutput: output, targetPrice: price, sourceDecimals: 18)
            let derived = limitOrderExpectedOutput(sourceAmount: source, sourceDecimals: 18, targetPrice: price)
            XCTAssertLessThanOrEqual(derived, output, "asked for \(requested)")
        }
    }

    func testSourceAmountIsZeroForNonPositiveInputs() {
        XCTAssertEqual(limitSourceAmount(forTargetOutput: 0, targetPrice: 16, sourceDecimals: 8), 0)
        XCTAssertEqual(limitSourceAmount(forTargetOutput: 10, targetPrice: 0, sourceDecimals: 8), 0)
        XCTAssertEqual(limitSourceAmount(forTargetOutput: -1, targetPrice: 16, sourceDecimals: 8), 0)
        XCTAssertEqual(limitSourceAmount(forTargetOutput: 10, targetPrice: -1, sourceDecimals: 8), 0)
    }

    func testSourceAmountBelowOneSmallestUnitIsZeroNotOne() {
        // Dust: an output too small to cost even one smallest unit must not
        // fabricate a deposit.
        let source = limitSourceAmount(
            forTargetOutput: Decimal(string: "0.000000001")!,
            targetPrice: 1_000,
            sourceDecimals: 8
        )
        XCTAssertEqual(source, 0)
    }

    func testSourceAmountIsQuantizedToDisplayPrecision() {
        // An 18-decimal source would otherwise derive a deposit carrying more
        // decimals than the Sell field renders, so the amount on screen would not
        // be the amount signed. The derived value must survive a round trip
        // through the field's own precision.
        let price = Decimal(string: "3.7")!
        let source = limitSourceAmount(forTargetOutput: 10, targetPrice: price, sourceDecimals: 18)

        let natural = Decimal(string: source.description)! / pow(Decimal(10), 18)
        var rounded = Decimal()
        var value = natural
        NSDecimalRound(&rounded, &value, limitAmountDisplayPrecision, .down)
        XCTAssertEqual(natural, rounded, "a derived deposit must not carry more decimals than the field shows")
    }

    // MARK: - clampLimitExpiryBlocks

    func testExpiryInsideTheRangeIsUnchanged() {
        let blocks = THORChainConstants.blocks(forHours: 24)
        XCTAssertEqual(clampLimitExpiryBlocks(blocks, maxBlocks: 43_200), blocks)
    }

    func testExpiryAboveTheCeilingClampsDown() {
        XCTAssertEqual(
            clampLimitExpiryBlocks(THORChainConstants.blocks(forHours: 24 * 7), maxBlocks: 43_200),
            43_200
        )
    }

    func testExpiryBelowTheFloorClampsUp() {
        XCTAssertEqual(
            clampLimitExpiryBlocks(1, maxBlocks: 43_200),
            THORChainConstants.minLimitSwapAgeBlocks
        )
    }

    func testExpiryClampHonoursACeilingBelowTheAppFloor() {
        // The floor is ours, the ceiling is the protocol's — so if a mimir ever
        // reported a cap under 10 minutes, the protocol has to win rather than
        // the clamp producing an out-of-range value from an empty range.
        XCTAssertEqual(clampLimitExpiryBlocks(600, maxBlocks: 60), 60)
        XCTAssertEqual(clampLimitExpiryBlocks(1, maxBlocks: 60), 60)
    }

    func testClampAndValidationAgreeOnTheFloorWhenTheCeilingIsLower() {
        // The regression this helper exists for: with a ceiling under the app
        // floor, the clamp produced the ceiling and validation then rejected that
        // very value, leaving no placeable expiry at all.
        let lowCeiling = 60
        let clamped = clampLimitExpiryBlocks(1, maxBlocks: lowCeiling)
        XCTAssertEqual(clamped, lowCeiling)
        XCTAssertGreaterThanOrEqual(clamped, effectiveMinExpiryBlocks(maxBlocks: lowCeiling))
    }

    func testEffectiveFloorIsTheAppFloorWhenTheCeilingIsHigher() {
        XCTAssertEqual(
            effectiveMinExpiryBlocks(maxBlocks: THORChainConstants.defaultLimitSwapMaxAgeBlocks),
            THORChainConstants.minLimitSwapAgeBlocks
        )
    }

    // MARK: - formatLimitExpiry

    func testFormatExpiryWholeHours() {
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forHours: 12)), "12h")
    }

    func testFormatExpiryWholeDays() {
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forHours: 72)), "3d")
    }

    func testFormatExpiryReproducesTheHistoricalPresetLabels() {
        // The preset pills render through this formatter, so it has to spell the
        // shipped set exactly. Splitting days from one day up would relabel the
        // 24h pill as "1d" — a change to a row that was meant to stay untouched.
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forHours: 12)), "12h")
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forHours: 24)), "24h")
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forHours: 72)), "3d")
    }

    func testFormatExpiryKeepsHoursBelowTwoDays() {
        // 36h reads better than "1d 12h" at this scale, and keeps the threshold
        // consistent with the 24h preset.
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forHours: 36)), "36h")
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forHours: 47)), "47h")
    }

    func testFormatExpiryOmitsZeroComponents() {
        // `2d`, not `2d 0h 0m` — and 48h is the first duration that splits days.
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forHours: 48)), "2d")
    }

    func testFormatExpiryMixedComponents() {
        let blocks = THORChainConstants.blocks(forMinutes: 2 * 1440 + 6 * 60 + 30)
        XCTAssertEqual(formatLimitExpiry(blocks: blocks), "2d 6h 30m")
    }

    func testFormatExpiryMinutesOnly() {
        XCTAssertEqual(formatLimitExpiry(blocks: THORChainConstants.blocks(forMinutes: 90)), "1h 30m")
    }

    func testFormatExpirySubMinuteDoesNotClaimADuration() {
        // Only reachable from a hand-built memo, never from the picker — floor it
        // to 0m rather than rendering an empty string.
        XCTAssertEqual(formatLimitExpiry(blocks: 5), "0m")
    }

    // MARK: - formatLimitPercent

    func testFormatPercentSignsPositiveExplicitly() {
        XCTAssertEqual(formatLimitPercent(5, locale: Locale(identifier: "en_US")), "+5.00")
    }

    func testFormatPercentUsesAsciiMinus() {
        XCTAssertEqual(
            formatLimitPercent(Decimal(string: "-2.5")!, locale: Locale(identifier: "en_US")),
            "-2.50"
        )
    }

    func testFormatPercentUsesTheGivenLocalesSeparator() {
        // Pinned rather than left to the host's ambient locale, which is what
        // makes a suite pass on one machine and fail on another.
        XCTAssertEqual(
            formatLimitPercent(Decimal(string: "-2.5")!, locale: Locale(identifier: "de_DE")),
            "-2,50"
        )
    }

    func testFormatPercentZero() {
        XCTAssertEqual(formatLimitPercent(0, locale: Locale(identifier: "en_US")), "+0.00")
    }

    func testFormatPercentShowsEveryStepperValueDistinctly() {
        // Two decimals against a 0.1 step: adjacent stepper values must never
        // render the same, or holding + would look frozen.
        let locale = Locale(identifier: "en_US")
        XCTAssertNotEqual(
            formatLimitPercent(Decimal(string: "7.5")!, locale: locale),
            formatLimitPercent(Decimal(string: "7.6")!, locale: locale)
        )
    }

    // MARK: - computePctFromMarket

    func testPctFromMarketAtMarket() {
        XCTAssertEqual(computePctFromMarket(targetPrice: 100, marketPrice: 100), 0)
    }

    func testPctFromMarketFivePercentAbove() {
        XCTAssertEqual(computePctFromMarket(targetPrice: 105, marketPrice: 100), 5)
    }

    func testPctFromMarketTenPercentBelow() {
        XCTAssertEqual(computePctFromMarket(targetPrice: 90, marketPrice: 100), -10)
    }

    func testPctFromMarketZeroMarketReturnsZero() {
        // Guard against divide-by-zero in degenerate cases.
        XCTAssertEqual(computePctFromMarket(targetPrice: 5, marketPrice: 0), 0)
    }

    // MARK: - evaluateWarning

    func testWarningWhenTargetEqualsMarket() {
        XCTAssertEqual(evaluateWarning(targetPrice: 100, marketPrice: 100), .priceAtOrBelowMarket)
    }

    func testWarningWhenTargetBelowMarket() {
        XCTAssertEqual(evaluateWarning(targetPrice: 95, marketPrice: 100), .priceAtOrBelowMarket)
    }

    func testNoWarningWhenTargetSlightlyAboveMarket() {
        XCTAssertNil(evaluateWarning(targetPrice: 105, marketPrice: 100))
    }

    func testNoWarningAtTwentyPercentBoundary() {
        // 1.2× exactly should NOT trigger the "may not fill" warning — only > 1.2×
        XCTAssertNil(evaluateWarning(targetPrice: 120, marketPrice: 100))
    }

    func testWarningWhenTargetWellAboveMarket() {
        XCTAssertEqual(evaluateWarning(targetPrice: 121, marketPrice: 100), .priceFarAboveMarket)
    }

    func testWarningWhenTargetTwiceMarket() {
        XCTAssertEqual(evaluateWarning(targetPrice: 200, marketPrice: 100), .priceFarAboveMarket)
    }

    // MARK: - Input parsing (locale-aware) — fund-safety

    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")

    func testParseLimitPriceParsesPlainDecimal() {
        XCTAssertEqual(parseLimitPrice("1.5", locale: enUS), Decimal(string: "1.5"))
    }

    func testParseLimitPriceParsesGroupedThousandsInUSLocale() {
        // FUND-CRITICAL: a pasted "1,000" must be 1000, not the naive parser's 1.0.
        XCTAssertEqual(parseLimitPrice("1,000", locale: enUS), Decimal(1000))
    }

    func testParseLimitPriceParsesGroupedMillionsInUSLocale() {
        XCTAssertEqual(parseLimitPrice("1,000,000", locale: enUS), Decimal(1_000_000))
    }

    func testParseLimitPricePreservesCommaDecimalLocaleIntent() {
        // In a comma-decimal locale "1,5" means 1.5 and "1.000,50" means 1000.5.
        XCTAssertEqual(parseLimitPrice("1,5", locale: deDE), Decimal(string: "1.5"))
        XCTAssertEqual(parseLimitPrice("1.000,50", locale: deDE), Decimal(string: "1000.5"))
    }

    func testParseLimitPricePreservesTrailingSeparatorWhileTyping() {
        // A lone trailing separator is an in-progress edit — must resolve to 1,
        // never 0 (zeroing the field mid-type would clobber the user's price).
        XCTAssertEqual(parseLimitPrice("1.", locale: enUS), Decimal(1))
    }

    func testParseLimitPriceEmptyIsZero() {
        XCTAssertEqual(parseLimitPrice("", locale: enUS), 0)
        XCTAssertEqual(parseLimitPrice("   ", locale: enUS), 0)
    }

    func testParseLimitAmountScalesGroupedThousands() {
        // FUND-CRITICAL: "1,000" of an 8-dec source is 1000 * 1e8 smallest units,
        // NOT the naive parser's 1 * 1e8 (which would deposit 1000× too little).
        XCTAssertEqual(
            parseLimitAmount("1,000", decimals: 8, locale: enUS),
            BigInt(1000) * BigInt(10).power(8)
        )
    }

    func testParseLimitAmountScalesFractional() {
        XCTAssertEqual(
            parseLimitAmount("1.5", decimals: 8, locale: enUS),
            BigInt(150_000_000)
        )
    }

    func testParseLimitAmountTruncatesBeyondDecimals() {
        // More fractional digits than the coin supports truncate toward zero.
        XCTAssertEqual(
            parseLimitAmount("0.123456789", decimals: 8, locale: enUS),
            BigInt(12_345_678)
        )
    }

    func testParseLimitAmountNonPositiveIsZero() {
        XCTAssertEqual(parseLimitAmount("", decimals: 8, locale: enUS), 0)
        XCTAssertEqual(parseLimitAmount("abc", decimals: 8, locale: enUS), 0)
        XCTAssertEqual(parseLimitAmount("0", decimals: 8, locale: enUS), 0)
    }
}
