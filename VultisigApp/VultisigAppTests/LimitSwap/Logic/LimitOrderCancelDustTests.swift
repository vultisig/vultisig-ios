//
//  LimitOrderCancelDustTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

final class LimitOrderCancelDustTests: XCTestCase {

    /// Generous by default so the ceiling only participates where a test is
    /// specifically about it. `decimals` defaults to 8 — THORChain's own fixed
    /// point — which is exactly the value that makes the rescale invisible, so
    /// every test that cares about it states it.
    private func dust(
        walletCore: BigInt,
        inbound: String?,
        decimals: Int = 8,
        ceiling: BigInt = BigInt(10).power(40),
        chain: String = "BTC"
    ) throws -> BigInt {
        try limitOrderCancelDustAmount(
            walletCoreDustFloor: walletCore,
            inboundDustThreshold: inbound,
            decimals: decimals,
            ceiling: ceiling,
            chainSymbol: chain
        )
    }

    /// THORChain's threshold is the one Bifrost enforces, and it is the one this
    /// codebase previously ignored entirely.
    func testUsesTheInboundThresholdWhenItExceedsTheLocalFloor() throws {
        // BTC: WalletCore floor 546 sats, THORChain threshold 1,000 sats.
        XCTAssertEqual(try dust(walletCore: 546, inbound: "1000"), BigInt(2000))
    }

    /// …and the local floor when IT is larger, because the signer refuses the
    /// output before anything is broadcast.
    func testUsesTheLocalFloorWhenItExceedsTheInboundThreshold() throws {
        XCTAssertEqual(try dust(walletCore: 10_000, inbound: "1000"), BigInt(20_000))
    }

    /// DOGE is the outlier — a whole 1 DOGE minimum — and it comes from the
    /// inbound row, not from WalletCore's much smaller floor.
    func testDogeTakesItsLargeThresholdFromTheInboundRow() throws {
        let amount = try dust(walletCore: 1_000_000, inbound: "100000000", chain: "DOGE")

        XCTAssertEqual(amount, BigInt(200_000_000))
    }

    func testAppliesTheSafetyMultiple() throws {
        let amount = try dust(walletCore: 0, inbound: "7")

        XCTAssertEqual(amount, BigInt(7) * limitOrderCancelDustSafetyMultiple)
    }

    // MARK: - THORChain's 1e8 units are not the chain's own

    /// ⚠️ **The 2026-07-22 regression, in one assertion.**
    ///
    /// THORChain publishes ETH's `dust_threshold` as `1000` — 1e8 units, i.e.
    /// 0.00001 ETH. Read as if it were already wei, doubling it produced a
    /// transaction worth 2000 wei (2e-15 ETH). It was signed, broadcast, and
    /// confirmed on Ethereum; Bifrost never saw an inbound, ~0.00016 ETH of gas
    /// was burned and the order kept resting. The correct attach is 2e13 wei.
    func testAnEighteenDecimalChainRescalesTheThresholdOutOfThorchainUnits() throws {
        let amount = try dust(walletCore: 0, inbound: "1000", decimals: 18, chain: "ETH")

        XCTAssertEqual(amount, BigInt("20000000000000"), "0.00002 ETH")
        XCTAssertNotEqual(amount, BigInt(2000), "the figure that was actually broadcast")
    }

    /// The other direction: GAIA carries FEWER decimals than THORChain, so the
    /// threshold scales down rather than up.
    func testAChainWithFewerDecimalsThanThorchainScalesTheThresholdDown() throws {
        // 1,000,000 in 1e8 units is 0.01 ATOM, which is 10,000 uatom.
        let amount = try dust(walletCore: 0, inbound: "1000000", decimals: 6, chain: "GAIA")

        XCTAssertEqual(amount, BigInt(20_000))
    }

    /// Scaling DOWN must round up: the threshold is a floor to clear, and
    /// truncation would land a unit under the very number being satisfied.
    func testScalingDownRoundsUpSoTheFloorIsStillCleared() {
        XCTAssertEqual(chainSmallestUnits(fromThorchainBaseUnits: BigInt(1001), decimals: 6), BigInt(11))
        XCTAssertEqual(chainSmallestUnits(fromThorchainBaseUnits: BigInt(1100), decimals: 6), BigInt(11))
        XCTAssertEqual(chainSmallestUnits(fromThorchainBaseUnits: BigInt(1), decimals: 6), BigInt(1))
    }

    /// The identity case — and the reason a UTXO-shaped test suite could not
    /// have caught any of the above.
    func testAnEightDecimalChainIsUnchangedByTheRescale() {
        XCTAssertEqual(chainSmallestUnits(fromThorchainBaseUnits: BigInt(100_000_000), decimals: 8), BigInt(100_000_000))
    }

    /// Every supported source chain, with the `dust_threshold` THORChain
    /// actually published on 2026-07-22, asserted in that chain's OWN smallest
    /// unit — and required to sit under the chain's real ceiling.
    ///
    /// The 18- and 6-decimal rows are the load-bearing ones: on the 8-decimal
    /// chains the rescale is the identity, which is precisely how an entire
    /// suite of them passed while Ethereum was broken by a factor of 1e10.
    func testEverySupportedSourceChainAttachesItsOwnSmallestUnits() throws {
        // (chain, decimals, published 1e8 threshold, expected attach in smallest units)
        let cases: [(Chain, Int, String, String)] = [
            (.bitcoin, 8, "1000", "2000"),
            (.bitcoinCash, 8, "10000", "20000"),
            (.litecoin, 8, "100000", "200000"),
            (.dogecoin, 8, "100000000", "200000000"),
            (.ethereum, 18, "1000", "20000000000000"),
            (.avalanche, 18, "100000", "2000000000000000"),
            (.bscChain, 18, "10000", "200000000000000"),
            (.gaiaChain, 6, "1000000", "20000")
        ]
        for (chain, decimals, threshold, expected) in cases {
            let amount = try dust(
                walletCore: 0,
                inbound: threshold,
                decimals: decimals,
                ceiling: try ceiling(for: chain, decimals: decimals),
                chain: "\(chain)"
            )

            XCTAssertEqual(amount, BigInt(expected), "\(chain) attach")
            XCTAssertGreaterThanOrEqual(
                amount,
                minimumObservableInbound(decimals: decimals),
                "\(chain) attach must be large enough for THORChain to observe"
            )
        }
    }

    // MARK: - Failing loudly rather than sending something invisible

    /// ⚠️ The guard the ETH rehearsal needed. An amount THORChain's own 1e8
    /// accounting truncates to zero raises no inbound at all — the transaction
    /// confirms, the fee is spent, and nothing is cancelled. Refusing beats
    /// quietly bumping it: a value landing here means the pipeline that produced
    /// it is wrong, and the bare minimum would still be under whatever THORChain
    /// really requires.
    func testAnAttachTooSmallForThorchainToObserveIsRefused() {
        XCTAssertThrowsError(try dust(walletCore: 0, inbound: "0", decimals: 18, chain: "ETH")) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .dustBelowObservableMinimum(chain: "ETH", computed: "0", minimum: "10000000000")
            )
        }
    }

    /// On an 18-decimal chain the observable minimum works out at 1e10 — the
    /// same EVM floor the protocol research derived independently from
    /// `ConvertAmount` truncating below it.
    func testTheObservableMinimumReproducesTheVerifiedEvmFloor() {
        XCTAssertEqual(minimumObservableInbound(decimals: 18), BigInt("10000000000"))
        XCTAssertEqual(minimumObservableInbound(decimals: 8), BigInt(1))
        XCTAssertEqual(minimumObservableInbound(decimals: 6), BigInt(1))
    }

    /// A zero-value L1 transaction carries no inbound for Bifrost to observe, so
    /// a chain reporting no floors at all is refused rather than guessed at.
    func testNeverReturnsZero() {
        XCTAssertThrowsError(try dust(walletCore: 0, inbound: "0")) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .dustBelowObservableMinimum(chain: "BTC", computed: "0", minimum: "1")
            )
        }
    }

    func testANegativePrecisionIsRejectedRatherThanRaisedToAPower() {
        XCTAssertThrowsError(try dust(walletCore: 0, inbound: "1000", decimals: -1)) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .unusableChainPrecision(chain: "BTC", decimals: -1)
            )
        }
    }

    /// ⚠️ The ceiling has to reject it INDEPENDENTLY, because it is evaluated as
    /// an argument to the function above and therefore runs before that guard.
    /// Reaching `BigInt(10).power(8 - decimals)` with a negative precision
    /// allocates absurdly, and with `Int.min` the subtraction traps outright —
    /// a crash where the contract says "throw".
    func testTheCeilingRejectsANegativePrecisionBeforeRaisingAnythingToAPower() {
        for decimals in [-1, Int.min] {
            XCTAssertThrowsError(
                try limitOrderCancelDustCeiling(for: .bitcoin, decimals: decimals, chainSymbol: "BTC")
            ) { error in
                XCTAssertEqual(
                    error as? LimitOrderCancelDustError,
                    .unusableChainPrecision(chain: "BTC", decimals: decimals)
                )
            }
        }
    }

    /// ⚠️ Fails closed. Guessing low means Bifrost silently ignores the cancel —
    /// fee spent, order untouched, indistinguishable from success.
    func testMissingThresholdThrowsRatherThanDefaulting() {
        XCTAssertThrowsError(try dust(walletCore: 546, inbound: nil)) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .inboundDustThresholdUnavailable(chain: "BTC")
            )
        }
    }

    /// ⚠️ `dust_threshold` is REMOTE and decides an irreversible donation, so a
    /// syntactically valid but absurd value must not be honoured and doubled.
    func testAnAbsurdRemoteThresholdIsRejectedRatherThanDonated() {
        XCTAssertThrowsError(
            try dust(walletCore: 546, inbound: "100000000000000", ceiling: BigInt(100_000))
        ) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .dustAmountExceedsCeiling(
                    chain: "BTC",
                    computed: "200000000000000",
                    ceiling: "100000"
                )
            )
        }
    }

    /// The ceiling is inclusive — a threshold landing exactly on it is fine.
    func testAmountExactlyAtTheCeilingIsAccepted() throws {
        XCTAssertEqual(try dust(walletCore: 0, inbound: "500", ceiling: BigInt(1000)), BigInt(1000))
    }

    // MARK: - The ceiling table, driven by the production predicates

    /// Every chain a cancel can be sent FROM as an L1 dust transfer — i.e.
    /// every chain that can reach the ceiling at all.
    ///
    /// ⚠️ **Composed from the production predicates, never listed.** That is the
    /// entire point of this section. The THORChain-native cases are excluded
    /// because `LimitOrderCancelPreparer.prepare` routes them to `MsgDeposit`
    /// before any dust is computed, and THORChain publishes no inbound row for
    /// itself.
    private var l1CancelSourceChains: [Chain] {
        Chain.allCases.filter {
            isThorchainRoutable(chain: $0)
                && !limitOrderCancelIsThorchainSourced(sourceChainRawValue: $0.rawValue)
        }
    }

    /// Every chain the ceiling table pins a threshold for. A superset of the
    /// above: pinning ahead of the routability gate is deliberate.
    private var pinnedChains: [Chain] {
        Chain.allCases.filter { limitOrderCancelPinnedDustThreshold(for: $0) != nil }
    }

    /// The native gas asset's precision, taken from the app's own catalog
    /// rather than restated here — a cancel is always signed with the source
    /// chain's gas asset, so this is the number production feeds the rescale.
    private func nativeDecimals(for chain: Chain) -> Int? {
        TokensStore.TokenSelectionAssets.first { $0.chain == chain && $0.isNativeToken }?.decimals
    }

    /// The production ceiling for `chain`, in that chain's smallest units —
    /// the exact call `limitOrderCancelDust(for:inbound:)` makes, without
    /// needing a `Coin`.
    private func ceiling(for chain: Chain, decimals: Int) throws -> BigInt {
        try limitOrderCancelDustCeiling(for: chain, decimals: decimals, chainSymbol: "\(chain)")
    }

    /// ⚠️ **The tripwire this file did not have.**
    ///
    /// The coverage loop below used to run over a hardcoded array — the same
    /// captured list the ceiling table itself was sized against — so it could
    /// not see a chain nobody remembered to add to it. That is structurally why
    /// XRP, TRON and SOL ended up on a `default` two to three orders of
    /// magnitude under their real requirement: not an oversight in the table so
    /// much as a test that could only ever confirm what the table already said.
    ///
    /// Driven off the production predicates instead, adding a chain to
    /// `thorchainChainPrefix` without pinning its threshold fails HERE, in CI,
    /// rather than shipping a chain whose every cancel its own ceiling refuses.
    func testEveryChainACancelCanBeSentFromHasAPinnedThreshold() {
        XCTAssertFalse(l1CancelSourceChains.isEmpty, "the predicates must resolve at least one source chain")
        for chain in l1CancelSourceChains {
            guard let pinned = limitOrderCancelPinnedDustThreshold(for: chain) else {
                XCTFail("""
                    \(chain) is a limit-swap cancel source with no pinned dust_threshold. \
                    Read it off /thorchain/inbound_addresses (1e8 units, verbatim) and add it to \
                    limitOrderCancelPinnedDustThreshold — every cancel from this chain is refused until you do.
                    """)
                continue
            }
            XCTAssertGreaterThan(pinned, 0, "\(chain) pinned threshold must be positive")
        }
    }

    /// The pinned table must be a faithful copy of what THORChain publishes —
    /// nothing invented, nothing missing.
    ///
    /// ⚠️ The second loop is the load-bearing one. Pinning a chain THORChain
    /// does NOT publish means inventing a bound out of nothing, which is the
    /// exact defect the natural-units table had: `.dash`, `.zcash` and `.noble`
    /// carried ceilings derived from no published threshold at all.
    func testThePinnedThresholdsAreVerbatimWhatThorchainPublishes() {
        // Captured 2026-08-03 from /thorchain/inbound_addresses, in THORChain's
        // 1e8 fixed point. Every chain the endpoint lists, and only those.
        let published: [Chain: BigInt] = [
            .bitcoin: BigInt(1000),
            .ethereum: BigInt(1000),
            .base: BigInt(1000),
            .bitcoinCash: BigInt(10_000),
            .bscChain: BigInt(10_000),
            .litecoin: BigInt(100_000),
            .avalanche: BigInt(100_000),
            .solana: BigInt(100_000),
            .gaiaChain: BigInt(1_000_000),
            .tron: BigInt(10_000_000),
            .dogecoin: BigInt(100_000_000),
            .ripple: BigInt(100_000_000)
        ]
        for (chain, threshold) in published {
            XCTAssertEqual(
                limitOrderCancelPinnedDustThreshold(for: chain), threshold,
                "\(chain) must be pinned to the value THORChain publishes"
            )
        }
        for chain in Chain.allCases where published[chain] == nil {
            XCTAssertNil(
                limitOrderCancelPinnedDustThreshold(for: chain),
                "\(chain) has no THORChain inbound row, so pinning it would be inventing a bound"
            )
        }
    }

    /// Every pinned chain's normal attach must sit comfortably under its
    /// ceiling, or cancelling would fail on the happy path.
    ///
    /// ⚠️ LTC and AVAX both publish a 0.001 threshold, so their normal attach is
    /// 0.002 — over the 0.001 ceiling they were once given. A ceiling sized
    /// against the wrong number does not fail safe: it refuses a cancel the user
    /// is entitled to make.
    func testEveryChainsPublishedThresholdSitsUnderItsCeiling() throws {
        for chain in pinnedChains {
            let decimals = try XCTUnwrap(nativeDecimals(for: chain), "\(chain) has no native asset in the catalog")
            let pinned = try XCTUnwrap(limitOrderCancelPinnedDustThreshold(for: chain))

            XCTAssertNoThrow(
                try dust(
                    walletCore: 0,
                    inbound: pinned.description,
                    decimals: decimals,
                    ceiling: try ceiling(for: chain, decimals: decimals),
                    chain: "\(chain)"
                ),
                "\(chain) normal attach must fit under its ceiling"
            )
        }
    }

    /// The ceiling is exactly `headroom` times the normal attach, on every
    /// chain and in every unit system.
    ///
    /// Stated against the ATTACH rather than against the formula, because the
    /// attach is what a reader cares about: this is how far THORChain may
    /// legitimately move a threshold before cancelling stops working. It also
    /// pins the composition — the ceiling is built FROM
    /// `limitOrderCancelDustSafetyMultiple`, so raising that widens the ceiling
    /// with it instead of quietly eating the margin.
    func testTheCeilingIsExactlyTheHeadroomTimesTheNormalAttach() throws {
        for chain in pinnedChains {
            let decimals = try XCTUnwrap(nativeDecimals(for: chain), "\(chain) has no native asset in the catalog")
            let pinned = try XCTUnwrap(limitOrderCancelPinnedDustThreshold(for: chain))
            let ceilingUnits = try ceiling(for: chain, decimals: decimals)
            let attach = try dust(
                walletCore: 0,
                inbound: pinned.description,
                decimals: decimals,
                ceiling: ceilingUnits,
                chain: "\(chain)"
            )

            XCTAssertEqual(
                ceilingUnits, attach * limitOrderCancelDustCeilingHeadroom,
                "\(chain) ceiling must be exactly the headroom over its normal attach"
            )
        }
    }

    /// ⚠️ **The OTHER floor has to fit under the ceiling too.**
    ///
    /// The attach is `max(walletCoreDustFloor, rescaledThreshold) × multiple`,
    /// and the ceiling is derived from only one of those two. On every chain
    /// today THORChain's threshold is the larger, so the ceiling is sized by the
    /// binding floor — but nothing in the types says so. A chain whose local
    /// signer floor exceeded ten times its published threshold would be refused
    /// on the happy path by a ceiling that never looked at it.
    ///
    /// Uses WalletCore's real per-chain value, the same call production makes.
    func testTheLocalSignerFloorAlsoFitsUnderEveryCeiling() throws {
        for chain in pinnedChains {
            let decimals = try XCTUnwrap(nativeDecimals(for: chain), "\(chain) has no native asset in the catalog")
            let pinned = try XCTUnwrap(limitOrderCancelPinnedDustThreshold(for: chain))
            let walletCoreFloor = BigInt(chain.coinType.getFixedDustThreshold())

            XCTAssertNoThrow(
                try dust(
                    walletCore: walletCoreFloor,
                    inbound: pinned.description,
                    decimals: decimals,
                    ceiling: try ceiling(for: chain, decimals: decimals),
                    chain: "\(chain)"
                ),
                "\(chain) attach with its real local floor (\(walletCoreFloor)) must fit under its ceiling"
            )
        }
    }

    /// ⚠️ **The headroom is a safety parameter, so its VALUE is pinned here.**
    ///
    /// Every other assertion in this section derives its expectations from the
    /// constant, which is deliberate — they should keep holding if it is ever
    /// retuned. The cost is that they are all satisfied by any value at all.
    /// This one is not: the headroom decides how much a wrong or hostile
    /// `dust_threshold` can cause the app to donate, so changing it has to be a
    /// conscious edit that lands here rather than a number that drifts.
    func testTheHeadroomIsTenTimesTheNormalAttach() {
        XCTAssertEqual(limitOrderCancelDustCeilingHeadroom, BigInt(10))
        XCTAssertEqual(limitOrderCancelDustSafetyMultiple, BigInt(2))
    }

    /// The ceilings themselves, spelled out in each chain's own smallest units.
    ///
    /// ⚠️ **Hand-computed, deliberately not derived.** Everything else here
    /// checks the formula against itself; these twelve numbers are the only
    /// place the formula is checked against arithmetic done independently of
    /// it. They are also what a reader needs to judge the trade — the natural
    /// units in the comments are the real answer to "how much could a bad
    /// remote value cost me on this chain".
    func testTheCeilingsAreTheExpectedAmountsInEachChainsOwnUnits() throws {
        // (chain, decimals, ceiling in smallest units, the same in natural units, ticker)
        let expected: [(Chain, Int, String, String, String)] = [
            (.bitcoin, 8, "20000", "0.0002", "BTC"),
            (.bitcoinCash, 8, "200000", "0.002", "BCH"),
            (.litecoin, 8, "2000000", "0.02", "LTC"),
            (.dogecoin, 8, "2000000000", "20", "DOGE"),
            (.ethereum, 18, "200000000000000", "0.0002", "ETH"),
            (.base, 18, "200000000000000", "0.0002", "ETH"),
            (.bscChain, 18, "2000000000000000", "0.002", "BNB"),
            (.avalanche, 18, "20000000000000000", "0.02", "AVAX"),
            (.gaiaChain, 6, "200000", "0.2", "ATOM"),
            (.tron, 6, "2000000", "2", "TRX"),
            (.ripple, 6, "20000000", "20", "XRP"),
            (.solana, 9, "20000000", "0.02", "SOL")
        ]
        XCTAssertEqual(expected.count, pinnedChains.count, "every pinned chain must have an expected ceiling here")

        for (chain, decimals, ceilingUnits, natural, ticker) in expected {
            let raw = try XCTUnwrap(BigInt(ceilingUnits))
            XCTAssertEqual(nativeDecimals(for: chain), decimals, "\(chain) native precision")
            XCTAssertEqual(
                try ceiling(for: chain, decimals: decimals), raw,
                "\(chain) ceiling should be \(natural) \(ticker)"
            )
            // The smallest-units figure and the natural-units one in the table
            // above must actually be the same amount, so neither column can be
            // wrong without the other noticing.
            XCTAssertEqual(
                exactNaturalUnitsString(raw, decimals: decimals), natural,
                "\(chain) ceiling in natural units"
            )
        }
    }

    /// The headroom's boundary, asserted from both sides on every pinned chain:
    /// a tenfold threshold rise still cancels, an elevenfold one is refused.
    ///
    /// This is the trade the ceiling IS. A legitimate protocol change should not
    /// brick cancelling; a remote value that has gone somewhere absurd must not
    /// be honoured and then doubled into an irreversible donation.
    func testATenfoldThresholdRiseStillCancelsAndMoreIsRefused() throws {
        for chain in pinnedChains {
            let decimals = try XCTUnwrap(nativeDecimals(for: chain), "\(chain) has no native asset in the catalog")
            let pinned = try XCTUnwrap(limitOrderCancelPinnedDustThreshold(for: chain))
            let ceilingUnits = try ceiling(for: chain, decimals: decimals)

            XCTAssertNoThrow(
                try dust(
                    walletCore: 0,
                    inbound: (pinned * limitOrderCancelDustCeilingHeadroom).description,
                    decimals: decimals,
                    ceiling: ceilingUnits,
                    chain: "\(chain)"
                ),
                "\(chain) must survive a threshold rise of the full headroom"
            )
            XCTAssertThrowsError(
                try dust(
                    walletCore: 0,
                    inbound: (pinned * (limitOrderCancelDustCeilingHeadroom + 1)).description,
                    decimals: decimals,
                    ceiling: ceilingUnits,
                    chain: "\(chain)"
                ),
                "\(chain) must refuse a threshold beyond the headroom"
            )
        }
    }

    /// ⚠️ **The regression this change exists for, in its own numbers.**
    ///
    /// XRP, TRON and SOL had no ceiling entry and fell to a `default` of 0.001
    /// natural units. Each row asserts BOTH halves: the attach really did exceed
    /// that default — so the cancel could never have been built, surfacing only
    /// as an error message that never resolves — and it fits the pinned ceiling
    /// now.
    ///
    /// BASE is here because it is the one that shows how invisible the trap was:
    /// THORChain publishes it too, and it survived the same `default` purely
    /// because its threshold happens to equal Ethereum's.
    func testTheChainsTheOldDefaultCeilingWouldHaveRefused() throws {
        // (chain, decimals, published 1e8 threshold, attach, the old 0.001-natural default,
        //  whether that default refused it)
        let cases: [(Chain, Int, String, String, BigInt, Bool)] = [
            (.ripple, 6, "100000000", "2000000", BigInt(1000), true),
            (.tron, 6, "10000000", "200000", BigInt(1000), true),
            (.solana, 9, "100000", "2000000", BigInt(1_000_000), true),
            (.base, 18, "1000", "20000000000000", BigInt(10).power(15), false)
        ]
        for (chain, decimals, threshold, expected, oldDefault, wasRefused) in cases {
            XCTAssertEqual(
                nativeDecimals(for: chain), decimals,
                "\(chain) native precision — the entire difference between the right attach and a wrong one"
            )

            let amount = try dust(
                walletCore: 0,
                inbound: threshold,
                decimals: decimals,
                ceiling: try ceiling(for: chain, decimals: decimals),
                chain: "\(chain)"
            )
            XCTAssertEqual(amount, BigInt(expected), "\(chain) attach")

            XCTAssertEqual(
                amount > oldDefault, wasRefused,
                "\(chain) against the removed default ceiling"
            )
        }
    }

    /// A chain with nothing pinned is refused BY NAME, rather than handed a
    /// number nobody checked against it.
    ///
    /// `.dash` stands in for the general case here: THORChain publishes no
    /// inbound row for it, so a cancel from it is impossible upstream of this
    /// anyway — but if the routability gate ever opened, this is the error a
    /// developer would see, and it says which chain is unconfigured.
    func testAChainWithNoPinnedThresholdIsRefusedByName() {
        XCTAssertNil(limitOrderCancelPinnedDustThreshold(for: .dash))
        XCTAssertThrowsError(
            try limitOrderCancelDustCeiling(for: .dash, decimals: 8, chainSymbol: "DASH")
        ) { error in
            XCTAssertEqual(error as? LimitOrderCancelDustError, .dustCeilingUnpinned(chain: "DASH"))
        }
    }

    func testANegativeLocalFloorFailsClosedRatherThanBeingIgnored() {
        XCTAssertThrowsError(try dust(walletCore: BigInt(-1), inbound: "1000"))
    }

    func testANegativeInboundThresholdThrows() {
        XCTAssertThrowsError(try dust(walletCore: 546, inbound: "-1")) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .malformedInboundDustThreshold(chain: "BTC", value: "-1")
            )
        }
    }

    func testMalformedThresholdThrows() {
        XCTAssertThrowsError(try dust(walletCore: 546, inbound: "not-a-number")) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .malformedInboundDustThreshold(chain: "BTC", value: "not-a-number")
            )
        }
    }

    // MARK: - Exact natural-units rendering

    /// ⚠️ This string becomes the transaction amount. A display formatter would
    /// round it, and dust rounded below THORChain's threshold is silently
    /// ignored by Bifrost — tx confirms, fee spent, nothing cancelled.
    func testRendersSmallEighteenDecimalAmountsWithoutRounding() {
        // 1e10 wei = 0.00000001 ETH — already at the edge of 8-dp display.
        XCTAssertEqual(exactNaturalUnitsString(BigInt(10).power(10), decimals: 18), "0.00000001")
        // One wei must not vanish.
        XCTAssertEqual(exactNaturalUnitsString(BigInt(1), decimals: 18), "0.000000000000000001")
        XCTAssertEqual(exactNaturalUnitsString(BigInt(3), decimals: 18), "0.000000000000000003")
    }

    func testRendersWholeAndFractionalAmounts() {
        XCTAssertEqual(exactNaturalUnitsString(BigInt(200_000_000), decimals: 8), "2")
        XCTAssertEqual(exactNaturalUnitsString(BigInt(2000), decimals: 8), "0.00002")
        XCTAssertEqual(exactNaturalUnitsString(BigInt(150_000_000), decimals: 8), "1.5")
        XCTAssertEqual(exactNaturalUnitsString(BigInt(0), decimals: 8), "0")
    }

    func testZeroDecimalsPassesThrough() {
        XCTAssertEqual(exactNaturalUnitsString(BigInt(1234), decimals: 0), "1234")
    }

    /// The round trip back to base units must be lossless — that is the whole
    /// point of not going through a formatter.
    func testRoundTripsBackToTheSameBaseUnits() {
        for (raw, decimals) in [(BigInt(1), 18), (BigInt(10).power(10), 18),
                                (BigInt(2000), 8), (BigInt(200_000_000), 8)] {
            let text = exactNaturalUnitsString(raw, decimals: decimals)
            let parts = text.split(separator: ".", maxSplits: 1)
            let whole = BigInt(String(parts[0])) ?? 0
            let fractionText = parts.count > 1 ? String(parts[1]) : ""
            let padded = fractionText + String(repeating: "0", count: decimals - fractionText.count)
            let fraction = padded.isEmpty ? BigInt(0) : (BigInt(padded) ?? 0)
            XCTAssertEqual(whole * BigInt(10).power(decimals) + fraction, raw, "\(text)")
        }
    }

    // MARK: - Memo length

    /// A gas-asset pair is comfortably inside even the 80-byte UTXO cap.
    func testGasAssetCancelMemoFitsAUtxoSource() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "BTC.BTC",
                sourceAmount1e8: BigInt(100_000_000),
                targetAsset: "ETH.ETH",
                tradeTarget: BigInt(15_979_057_441)
            )
        )

        XCTAssertLessThanOrEqual(memo.utf8.count, 80)
        XCTAssertTrue(limitOrderCancelMemoFits(memo, sourceChainKind: .UTXO))
    }

    /// ⚠️ The combination v1 must block: a contract-suffixed ERC20 target cannot
    /// be shortened (no short codes, no fuzzy matching) and the amounts cannot be
    /// rounded (they define the ratio bucket), so there is no way to make this
    /// fit 80 bytes.
    func testErc20TargetFromAUtxoSourceDoesNotFit() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "BTC.BTC",
                sourceAmount1e8: BigInt(123_456_789),
                targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                tradeTarget: BigInt(9_876_543_210)
            )
        )

        XCTAssertGreaterThan(memo.utf8.count, 80)
        XCTAssertFalse(limitOrderCancelMemoFits(memo, sourceChainKind: .UTXO))
        // The same memo is fine from an EVM source, where the budget is 250.
        XCTAssertTrue(limitOrderCancelMemoFits(memo, sourceChainKind: .EVM))
    }

    /// ⚠️ The gate has to be handed the memo that will actually be signed.
    ///
    /// The 2026-07-21 rehearsal measured the abbreviated spelling — 49 bytes for
    /// a memo that is 85 — so the difference is not cosmetic: it is 36 bytes per
    /// token leg, which is exactly the margin that decides a UTXO source. Sized
    /// short, the gate passes a cancel it should block, and the user pays a fee
    /// for a truncated `OP_RETURN` that can never match.
    func testTheAbbreviatedSpellingWouldHavePassedAGateTheFullOneFails() throws {
        let abbreviated = "m=<:123456789BTC.BTC:9876543210ETH.USDC-06EB48:0"
        let full = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "BTC.BTC",
                sourceAmount1e8: BigInt(123_456_789),
                targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                tradeTarget: BigInt(9_876_543_210)
            )
        )

        XCTAssertTrue(limitOrderCancelMemoFits(abbreviated, sourceChainKind: .UTXO))
        XCTAssertFalse(limitOrderCancelMemoFits(full, sourceChainKind: .UTXO))
        XCTAssertEqual(full.utf8.count - abbreviated.utf8.count, 36, "one contract, spelled out")
    }

    /// The rehearsal's own pair, from THORChain: 85 bytes is nowhere near the
    /// 250-byte budget a `MsgDeposit` has, so spelling the asset out costs this
    /// route nothing.
    func testTheRehearsalMemoFitsAThorchainSourceComfortably() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(370_939_666),
                targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                tradeTarget: BigInt(167_889_485)
            )
        )

        XCTAssertEqual(memo.utf8.count, 85)
        XCTAssertTrue(limitOrderCancelMemoFits(memo, sourceChainKind: Chain.thorChain.chainType))
    }

    /// The generated-memo tests above prove realistic cases but not the boundary
    /// itself, which is where an off-by-one would actually bite.
    func testTheUtxoBoundaryIsInclusiveAtEightyBytes() {
        let exactly80 = String(repeating: "a", count: 80)
        let exactly81 = String(repeating: "a", count: 81)

        XCTAssertTrue(limitOrderCancelMemoFits(exactly80, sourceChainKind: .UTXO))
        XCTAssertFalse(limitOrderCancelMemoFits(exactly81, sourceChainKind: .UTXO))
    }

    /// Counted in UTF-8 BYTES, not `Character`s — OP_RETURN's cap is on encoded
    /// bytes, and a `count`-based check would let an over-long memo through.
    func testLengthIsCountedInUtf8BytesNotCharacters() {
        // 40 characters, 80 bytes.
        let twoByteChars = String(repeating: "é", count: 40)
        XCTAssertEqual(twoByteChars.count, 40)
        XCTAssertEqual(twoByteChars.utf8.count, 80)
        XCTAssertTrue(limitOrderCancelMemoFits(twoByteChars, sourceChainKind: .UTXO))

        // 41 characters, 82 bytes — under a Character count, over the real cap.
        let overflowing = String(repeating: "é", count: 41)
        XCTAssertLessThan(overflowing.count, 80)
        XCTAssertFalse(limitOrderCancelMemoFits(overflowing, sourceChainKind: .UTXO))
    }
}
