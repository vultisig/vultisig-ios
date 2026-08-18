//
//  HeaderCollapseProgressTests.swift
//  VultisigAppTests
//

import Combine
import XCTest

@testable import VultisigApp

/// The vault-home top bar collapses as the user scrolls. The acceptance
/// criterion for that transition is that the large balance in the content and
/// the balance in the top bar are *never legible at the same time* — these
/// tests pin that as an algebraic property of the two fade ramps rather than
/// something that has to be eyeballed.
final class HeaderCollapseProgressTests: XCTestCase {

    /// The scroll views' top inset: the offset reported at scroll position zero.
    private let resting: CGFloat = 78
    private let distance = HeaderCollapseProgress.defaultDistance

    private func makeProgress(scrolled: CGFloat) -> HeaderCollapseProgress {
        HeaderCollapseProgress(offset: resting - scrolled, restingOffset: resting)
    }

    // MARK: - Progress

    func testRestingOffsetIsFullyExpanded() {
        let progress = makeProgress(scrolled: 0)
        XCTAssertEqual(progress.value, 0)
        XCTAssertEqual(progress, .expanded)
        XCTAssertEqual(progress.expandedOpacity, 1)
        XCTAssertEqual(progress.collapsedOpacity, 0)
        XCTAssertFalse(progress.isCollapsed)
    }

    func testScrollingTheFullDistanceIsFullyCollapsed() {
        let progress = makeProgress(scrolled: distance)
        XCTAssertEqual(progress.value, 1)
        XCTAssertEqual(progress.expandedOpacity, 0)
        XCTAssertEqual(progress.collapsedOpacity, 1)
        XCTAssertTrue(progress.isCollapsed)
    }

    func testScrollingPastTheDistanceStaysCollapsed() {
        XCTAssertEqual(makeProgress(scrolled: distance * 10).value, 1)
    }

    /// Pulling down past the top (rubber band, pull-to-refresh) reports an
    /// offset *larger* than the resting one. It must not drive the progress
    /// negative or fade anything.
    func testOverscrollStaysFullyExpanded() {
        let progress = makeProgress(scrolled: -200)
        XCTAssertEqual(progress.value, 0)
        XCTAssertEqual(progress.expandedOpacity, 1)
        XCTAssertEqual(progress.collapsedOpacity, 0)
    }

    func testProgressIsMonotonicInScrollDistance() {
        var previous = makeProgress(scrolled: -20).value
        for step in stride(from: CGFloat(-20), through: distance + 40, by: 1) {
            let current = makeProgress(scrolled: step).value
            XCTAssertGreaterThanOrEqual(current, previous, "progress went backwards at \(step)pt")
            previous = current
        }
    }

    func testADegenerateDistanceFallsBackToAThreshold() {
        let expanded = HeaderCollapseProgress(offset: resting, restingOffset: resting, distance: 0)
        let collapsed = HeaderCollapseProgress(offset: resting - 1, restingOffset: resting, distance: 0)
        XCTAssertEqual(expanded.value, 0)
        XCTAssertEqual(collapsed.value, 1)
    }

    // MARK: - The two ramps

    func testExpandedContentFadesOutOverTheFirstHalf() {
        XCTAssertEqual(makeProgress(scrolled: 0).expandedOpacity, 1)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.25).expandedOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.5).expandedOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.75).expandedOpacity, 0)
    }

    func testCollapsedContentFadesInOverTheSecondHalf() {
        XCTAssertEqual(makeProgress(scrolled: 0).collapsedOpacity, 0)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.25).collapsedOpacity, 0)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.5).collapsedOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.75).collapsedOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(makeProgress(scrolled: distance).collapsedOpacity, 1)
    }

    /// The top bar swaps its toolbar buttons for the balance at the midpoint —
    /// the single point where both ramps are zero, so nothing pops.
    func testTheSwapHappensWhereBothRampsAreZero() {
        let progress = makeProgress(scrolled: distance * 0.5)
        XCTAssertTrue(progress.isCollapsed)
        XCTAssertEqual(progress.expandedOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(progress.collapsedOpacity, 0, accuracy: 0.0001)
    }

    /// The whole point of the change: swept across the transition (and well
    /// past both ends of it) at sub-point resolution, at most one of the two
    /// balances is ever drawn.
    func testTheTwoBalancesAreNeverBothVisible() {
        for step in stride(from: CGFloat(-40), through: distance + 40, by: 0.25) {
            let progress = makeProgress(scrolled: step)
            XCTAssertTrue(
                progress.expandedOpacity == 0 || progress.collapsedOpacity == 0,
                "both legible at \(step)pt: expanded \(progress.expandedOpacity), collapsed \(progress.collapsedOpacity)"
            )
        }
    }

    // MARK: - The guards the ramps drive

    /// A faded-out view is still laid out: it keeps taking taps and is still
    /// read out by VoiceOver unless something says otherwise. `headerCollapseOpacity`
    /// says otherwise by comparing the ramp against zero *exactly* — so a ramp
    /// that merely approached zero, or landed on a float residue, would leave an
    /// invisible balance or an invisible History/Settings button live. Pin the
    /// hard zeros at both ends of both ramps.
    func testBothRampsReachExactlyZero() {
        XCTAssertEqual(makeProgress(scrolled: distance * 0.5).expandedOpacity, 0)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.75).expandedOpacity, 0)
        XCTAssertEqual(makeProgress(scrolled: distance).expandedOpacity, 0)

        XCTAssertEqual(makeProgress(scrolled: 0).collapsedOpacity, 0)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.25).collapsedOpacity, 0)
        XCTAssertEqual(makeProgress(scrolled: distance * 0.5).collapsedOpacity, 0)
    }

    /// The two guards are complementary predicates over the same value —
    /// `allowsHitTesting(opacity > 0)` and `accessibilityHidden(opacity == 0)` —
    /// so every scroll position must satisfy exactly one of them. A ramp that
    /// went negative (or NaN) would satisfy neither, which is precisely the
    /// defect the guards exist to prevent: invisible, and still exposed.
    func testTheGuardPredicatesPartitionTheWholeSweep() {
        for step in stride(from: CGFloat(-40), through: distance + 40, by: 0.25) {
            let progress = makeProgress(scrolled: step)
            for opacity in [progress.expandedOpacity, progress.collapsedOpacity] {
                XCTAssertTrue(
                    (opacity > 0) != (opacity == 0),
                    "opacity \(opacity) at \(step)pt is neither legible nor a hard zero"
                )
            }
        }
    }

    /// The top bar's trailing slot draws whichever side `isCollapsed` selects,
    /// and ramps it with the matching opacity. Swept across the transition, the
    /// side that is *not* drawn is always at a hard zero, so the side that is
    /// drawn is the only thing the guards ever have to keep alive — the swap
    /// can never hand over while the outgoing side is still legible.
    func testTheDrawnSideOfTheSwapIsAlwaysTheOnlyLiveOne() {
        for step in stride(from: CGFloat(-40), through: distance + 40, by: 0.25) {
            let progress = makeProgress(scrolled: step)
            let shownOpacity = progress.isCollapsed ? progress.collapsedOpacity : progress.expandedOpacity
            let hiddenOpacity = progress.isCollapsed ? progress.expandedOpacity : progress.collapsedOpacity

            XCTAssertEqual(hiddenOpacity, 0, "the slot that is not drawn must be at a hard zero at \(step)pt")
            XCTAssertGreaterThanOrEqual(shownOpacity, 0, "a ramp went negative at \(step)pt")
            XCTAssertLessThanOrEqual(shownOpacity, 1, "a ramp overshot at \(step)pt")
        }
    }

    // MARK: - Per-tab store

    @MainActor
    func testStoreStartsExpandedForEveryTab() {
        let collapse = HomeHeaderCollapse()
        XCTAssertEqual(collapse.progress(for: .wallet), .expanded)
        XCTAssertEqual(collapse.progress(for: .defi), .expanded)
        XCTAssertEqual(collapse.progress(for: .camera), .expanded)
    }

    @MainActor
    func testStoreKeepsTheTabsIndependent() {
        let collapse = HomeHeaderCollapse()
        collapse.update(tab: .wallet, offset: resting - distance, restingOffset: resting)

        XCTAssertEqual(collapse.progress(for: .wallet).value, 1)
        XCTAssertEqual(collapse.progress(for: .defi), .expanded)

        // Scrolled against the DeFi tab's own (longer) ramp, not the wallet's.
        let defiDistance = HeaderCollapseProgress.distance(for: .defi)
        collapse.update(tab: .defi, offset: resting - defiDistance * 0.25, restingOffset: resting)
        XCTAssertEqual(collapse.progress(for: .defi).value, 0.25, accuracy: 0.0001)
        XCTAssertEqual(collapse.progress(for: .wallet).value, 1, "the wallet tab must not move")
    }

    /// The offset arrives on every layout pass, so the store has to stay quiet
    /// unless the progress actually moved — which, outside the transition
    /// window, it never does.
    @MainActor
    func testStoreOnlyPublishesWhenTheProgressChanges() {
        let collapse = HomeHeaderCollapse()
        var publishes = 0
        let cancellable = collapse.objectWillChange.sink { _ in publishes += 1 }
        defer { cancellable.cancel() }

        // Well past the end of the transition: 200 frames, saturated at 1.
        for step in 0..<200 {
            let offset = resting - distance * 2 - CGFloat(step)
            collapse.update(tab: .wallet, offset: offset, restingOffset: resting)
        }

        XCTAssertEqual(publishes, 1, "a saturated progress must publish once, not once per frame")
        XCTAssertEqual(collapse.progress(for: .wallet).value, 1)
    }

    @MainActor
    func testStoreIgnoresTheAccessoryTab() {
        let collapse = HomeHeaderCollapse()
        collapse.update(tab: .camera, offset: resting - distance, restingOffset: resting)
        XCTAssertEqual(collapse.progress(for: .camera), .expanded)
    }

    // MARK: - Per-tab ramp length

    /// The reported bug: the DeFi banner went fully transparent about halfway
    /// down its own height, and `.opacity` does not reclaim layout — so stopping
    /// mid-scroll left a blank gap where the card still was.
    ///
    /// The expanded ramp finishes at half the collapse distance, so the distance
    /// has to be twice the height of whatever it fades.
    func testDefiRampIsTwiceTheBannerHeight() {
        XCTAssertEqual(
            HeaderCollapseProgress.distance(for: .defi),
            DefiMainBalanceView.bannerHeight * 2,
            "the ramp and the banner it fades must not drift apart"
        )
    }

    func testWalletRampIsUnchanged() {
        XCTAssertEqual(HeaderCollapseProgress.distance(for: .wallet), HeaderCollapseProgress.defaultDistance)
        XCTAssertEqual(HeaderCollapseProgress.distance(for: .camera), HeaderCollapseProgress.defaultDistance)
    }

    /// The acceptance criterion in the issue, stated directly: the banner is
    /// still drawn everywhere it is still on screen, and reaches zero exactly
    /// where it has finished scrolling past.
    func testDefiBannerIsStillDrawnWhileAnyOfItIsOnScreen() {
        let banner = DefiMainBalanceView.bannerHeight
        let defiDistance = HeaderCollapseProgress.distance(for: .defi)

        func progress(scrolled: CGFloat) -> HeaderCollapseProgress {
            HeaderCollapseProgress(offset: resting - scrolled, restingOffset: resting, distance: defiDistance)
        }

        // Every point at which part of the card is still on screen.
        for step in stride(from: CGFloat(0), to: banner, by: 0.5) {
            XCTAssertGreaterThan(
                progress(scrolled: step).expandedOpacity, 0,
                "\(banner - step)pt of banner is still on screen at \(step)pt, but it is already invisible"
            )
        }

        XCTAssertEqual(progress(scrolled: banner).expandedOpacity, 0, accuracy: 0.0001,
                       "and it is gone exactly when the banner has scrolled past")
    }

    /// The old ramp's zero point. Before the fix the banner was fully
    /// transparent here with ~80pt of it still on screen — the blank gap.
    func testDefiBannerIsMostlyVisibleAtTheOldRampsZeroPoint() {
        let oldZero = HeaderCollapseProgress.defaultDistance / 2
        let progress = HeaderCollapseProgress(
            offset: resting - oldZero,
            restingOffset: resting,
            distance: HeaderCollapseProgress.distance(for: .defi)
        )
        XCTAssertGreaterThan(progress.expandedOpacity, 0.5,
                             "most of the banner is still on screen here, so most of it must still be drawn")
    }

    /// The invariant the rest of this file pins for the default ramp has to hold
    /// for the DeFi ramp too — a longer ramp must not let the banner and the top
    /// bar's balance be legible at the same time.
    func testTheTwoBalancesAreNeverBothVisibleOnTheDefiRamp() {
        let defiDistance = HeaderCollapseProgress.distance(for: .defi)
        for step in stride(from: CGFloat(-40), through: defiDistance + 40, by: 0.25) {
            let progress = HeaderCollapseProgress(
                offset: resting - step,
                restingOffset: resting,
                distance: defiDistance
            )
            XCTAssertTrue(
                progress.expandedOpacity == 0 || progress.collapsedOpacity == 0,
                "both legible at \(step)pt: expanded \(progress.expandedOpacity), collapsed \(progress.collapsedOpacity)"
            )
        }
    }
}
