//
//  FunctionCallReachabilityTests.swift
//  VultisigAppTests
//
//  Pins the reachability contract between the three tables that decide what
//  the Function (memo) screen shows:
//
//    * `CoinAction.memoChains`          — which chains show the button at all
//    * `FunctionCallType.getCases`      — what the dropdown lists
//    * `FunctionCallType.getDefault`    — which entry the dropdown opens on
//
//  None of the three is derived from the others, so every mismatch is a silent
//  runtime defect rather than a compile error: cases offered on a chain with no
//  button are dead code, a chain with a button and no cases opens an empty
//  selector, and a default the dropdown does not list strands the user on a
//  screen they cannot navigate back to.
//
//  `FunctionCallInstance.getDefault` — which form the screen actually builds —
//  used to be a fourth table here. It is now derived from `getDefault`, so the
//  pairing is pinned where that derivation lives: `FunctionCallMigrationSeamTests`.
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallReachabilityTests: XCTestCase {

    // MARK: - memoChains ⟷ getCases

    /// Every chain that shows the Function button offers at least one function.
    /// A chain listed in `memoChains` with no cases renders an empty selector.
    func testEveryMemoChainHasCases() {
        for chain in CoinAction.memoChains {
            let coin = nativeCoin(for: chain)
            XCTAssertFalse(
                FunctionCallType.getCases(for: coin).isEmpty,
                "\(chain) shows the Function button but getCases is empty"
            )
        }
    }

    /// The reverse direction: cases offered on a chain that never shows the
    /// button are unreachable. This is what made the Noble/Akash IBC arms dead.
    func testNoChainOutsideMemoChainsOffersCases() {
        for chain in Chain.allCases where !CoinAction.memoChains.contains(chain) {
            let coin = nativeCoin(for: chain)
            XCTAssertTrue(
                FunctionCallType.getCases(for: coin).isEmpty,
                "\(chain) offers \(FunctionCallType.getCases(for: coin)) but never shows the Function button"
            )
        }
    }

    // MARK: - getDefault ∈ getCases

    /// The screen opens on `getDefault` and lists `getCases`; a default outside
    /// that list is a form the dropdown cannot return the user to.
    func testEveryMemoChainDefaultIsOffered() {
        for chain in CoinAction.memoChains {
            let coin = nativeCoin(for: chain)
            let cases = FunctionCallType.getCases(for: coin)
            let selected = FunctionCallType.getDefault(for: coin)
            XCTAssertTrue(
                cases.contains(selected),
                "\(chain) opens on \(selected) but the dropdown only offers \(cases)"
            )
        }
    }

    // MARK: - The two default factories agree
    //
    // Moved, not dropped. `FunctionCallInstance.getDefault` no longer re-derives
    // the chain mapping — it reads `FunctionCallType.getDefault` and answers nil
    // where that operation has moved to `Features/FunctionTransaction/` — so the
    // two can no longer name different operations at all. What is left to pin is
    // that they agree on whether a legacy form exists, and that is asserted over
    // every chain rather than only the memo chains by
    // `FunctionCallMigrationSeamTests`
    // `.testTheTwoDefaultFactoriesAgreeOnWhichChainsHaveNoLegacyForm`.

    // MARK: - Helpers

    /// A native coin for `chain`, carrying the chain's own ticker so
    /// ticker-sensitive default branches see a realistic value.
    private func nativeCoin(for chain: Chain) -> Coin {
        FunctionCallFixture.makeCoin(
            chain,
            ticker: chain.ticker,
            decimals: 8,
            isNative: true
        )
    }
}
