//
//  ChainDefaultActionsTests.swift
//  VultisigApp
//
//  Pins the `.swap` action surfacing in `Chain.defaultActions`. After
//  `Coin+ChainAction.swift` was refactored to derive swap presence from
//  `Chain.isSwapAvailable` instead of the hand-maintained
//  `CoinAction.swapChains` array, four chains changed user-visible
//  behavior: polygonV2 lost `.swap`; cardano / sui / ton gained it. These
//  explicit asserts guard against a silent regression of that flip, plus
//  one already-consistent chain on each side as a sanity axis.
//
//  `defaultActions` runs through `Array<CoinAction>.filtered`, which strips
//  `.swap` when `SwapFeatureGate.canSwap()` returns false (locale-gated:
//  GB / JP / MY). To keep the test deterministic across CI / dev machines
//  we `XCTSkipUnless(SwapFeatureGate.canSwap())` — the truth-table coverage
//  in `ChainSwapAvailabilityTests` still pins `isSwapAvailable` itself in
//  every locale.
//

@testable import VultisigApp
import XCTest

final class ChainDefaultActionsTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            SwapFeatureGate.canSwap(),
            "SwapFeatureGate gates .swap out of defaultActions in restricted locales (GB / JP / MY); " +
            "skipping the swap-presence assertions for this run."
        )
    }

    // MARK: - Behavior changes pinned by the swapChains -> isSwapAvailable refactor

    func testPolygonV2DoesNotShowSwap() {
        XCTAssertFalse(
            Chain.polygonV2.defaultActions.contains(.swap),
            "polygonV2 was stale in the old swapChains list; isSwapAvailable=false is canonical."
        )
    }

    func testCardanoShowsSwap() {
        XCTAssertTrue(
            Chain.cardano.defaultActions.contains(.swap),
            "cardano was missing from the old swapChains list; isSwapAvailable=true is canonical."
        )
    }

    func testSuiShowsSwap() {
        XCTAssertTrue(
            Chain.sui.defaultActions.contains(.swap),
            "sui was missing from the old swapChains list; isSwapAvailable=true is canonical."
        )
    }

    func testTonShowsSwap() {
        XCTAssertTrue(
            Chain.ton.defaultActions.contains(.swap),
            "ton was missing from the old swapChains list; isSwapAvailable=true is canonical."
        )
    }

    // MARK: - Stable chains (sanity axis)
    //
    // These were already consistent between the old swapChains list and
    // isSwapAvailable. They guard against a refactor that accidentally
    // collapses every chain into one branch.

    func testBitcoinShowsSwap() {
        XCTAssertTrue(Chain.bitcoin.defaultActions.contains(.swap))
    }

    func testPolkadotDoesNotShowSwap() {
        XCTAssertFalse(Chain.polkadot.defaultActions.contains(.swap))
    }
}
