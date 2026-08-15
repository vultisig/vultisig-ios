//
//  FunctionCallReachabilityTests.swift
//  VultisigAppTests
//
//  Pins the reachability contract between the tables that decide what the
//  Function entry point shows:
//
//    * `CoinAction.memoChains`          — which chains show the button at all
//    * `FunctionCallType.getCases`      — what the action list lists
//    * `FunctionCallType.getDefault`    — which entry a single-action chain opens on
//
//  None is derived from the others, so every mismatch is a silent runtime
//  defect rather than a compile error: cases offered on a chain with no
//  button are dead code, a chain with a button and no cases opens an empty
//  list, and a default the chain does not list strands the user on a
//  selection it cannot navigate back to.
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
    ///
    /// Gaia is exempt: it offers two operations and both are migrated, so
    /// there is no unmigrated case left to point the default at. It falls
    /// back to `.custom`, which is not one of Gaia's own cases — harmless,
    /// because every row Gaia offers routes through the action list to a
    /// migrated screen and never consults this default at all. See
    /// `FunctionCallMigrationSeamTests.testGaiaDefaultIsVestigialAndUnreachable`.
    func testEveryMemoChainDefaultIsOffered() {
        for chain in CoinAction.memoChains where chain != .gaiaChain {
            let coin = nativeCoin(for: chain)
            let cases = FunctionCallType.getCases(for: coin)
            let selected = FunctionCallType.getDefault(for: coin)
            XCTAssertTrue(
                cases.contains(selected),
                "\(chain) opens on \(selected) but the dropdown only offers \(cases)"
            )
        }
    }

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
