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

        collapse.update(tab: .defi, offset: resting - distance * 0.25, restingOffset: resting)
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
}
