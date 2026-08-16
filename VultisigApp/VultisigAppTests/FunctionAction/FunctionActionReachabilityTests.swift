//
//  FunctionActionReachabilityTests.swift
//  VultisigAppTests
//
//  Pins the reachability contract between the two tables that decide what the
//  Functions entry point shows:
//
//    * `CoinAction.memoChains`      — which chains show the button at all
//    * `FunctionAction.offered(on:)` — what the button leads to
//
//  Neither is derived from the other, so every mismatch is a silent runtime
//  defect rather than a compile error: operations offered on a chain with no
//  button are dead code, and a chain with a button and nothing behind it is a
//  button that leads to an empty screen.
//
//  There used to be a third and a fourth table — `getDefault`, which said which
//  entry the dropdown opened on, and `FunctionCallInstance.getDefault`, which
//  built the form underneath it. Both are gone with the dropdown: a row carries
//  its own destination, so no default decides where anyone lands, and there is
//  no per-chain default left to keep honest.
//

import XCTest
@testable import VultisigApp

@MainActor
final class FunctionActionReachabilityTests: XCTestCase {

    // MARK: - memoChains ⟷ offered(on:)

    /// Every chain that shows the Functions button offers at least one
    /// operation. A chain listed in `memoChains` with nothing behind it renders
    /// an empty list — which is what the THORChain forks did.
    func testEveryMemoChainOffersAnOperation() {
        for chain in CoinAction.memoChains {
            let coin = nativeCoin(for: chain)
            XCTAssertFalse(
                FunctionAction.offered(on: coin).isEmpty,
                "\(chain) shows the Functions button with nothing behind it"
            )
        }
    }

    /// The reverse direction: operations offered on a chain that never shows the
    /// button are unreachable. This is what made the Noble/Akash IBC arms dead.
    func testNoChainOutsideMemoChainsOffersAnOperation() {
        for chain in Chain.allCases where !CoinAction.memoChains.contains(chain) {
            let coin = nativeCoin(for: chain)
            XCTAssertTrue(
                FunctionAction.offered(on: coin).isEmpty,
                "\(chain) offers \(FunctionAction.offered(on: coin)) but never shows the Functions button"
            )
        }
    }

    /// Every operation the enum has is offered by at least one chain. An
    /// operation no chain lists has a screen, an intent and a builder, and no
    /// way in — the state the Noble/Akash arms were in from the other side.
    func testEveryOperationIsOfferedSomewhere() {
        let offered = Set(CoinAction.memoChains.flatMap { FunctionAction.offered(on: nativeCoin(for: $0)) })
        for action in FunctionAction.allCases {
            XCTAssertTrue(
                offered.contains(action),
                "\(action.rawValue) is not offered on any chain that shows the Functions button"
            )
        }
    }

    // MARK: - Helpers

    /// A native coin for `chain`, carrying the chain's own ticker so
    /// ticker-sensitive branches see a realistic value.
    private func nativeCoin(for chain: Chain) -> Coin {
        FunctionActionFixture.makeCoin(
            chain,
            ticker: chain.ticker,
            decimals: 8,
            isNative: true
        )
    }
}
