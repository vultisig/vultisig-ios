//
//  ChainDefaultActionsTests.swift
//  VultisigApp
//
//  Pins the `.swap` action surfacing in `Chain.defaultActions`. After
//  `Coin+ChainAction.swift` was refactored to derive swap presence from
//  `Chain.isSwapAvailable` instead of the hand-maintained
//  `CoinAction.swapChains` array, three chains gained `.swap`:
//  cardano / sui / ton (they were missing from the stale `swapChains`
//  list). polygonV2 — also stale in the old list — was kept on by
//  flipping `Chain.isSwapAvailable` to include it as the canonical truth.
//  These explicit asserts guard against a silent regression of that flip,
//  plus one already-consistent chain on each side as a sanity axis.
//

@testable import VultisigApp
import XCTest

final class ChainDefaultActionsTests: XCTestCase {

    // MARK: - Behavior changes pinned by the swapChains -> isSwapAvailable refactor

    func testPolygonV2ShowsSwap() {
        XCTAssertTrue(
            Chain.polygonV2.defaultActions.contains(.swap),
            "polygonV2 was stale in the old swapChains list; isSwapAvailable=true is canonical."
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
