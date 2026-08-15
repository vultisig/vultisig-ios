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
//    * `FunctionCallInstance.getDefault`— which form the screen actually builds
//
//  None of the four is derived from the others, so every mismatch is a silent
//  runtime defect rather than a compile error: cases offered on a chain with no
//  button are dead code, a chain with a button and no cases opens an empty
//  selector, and a default the dropdown does not list (or a form that disagrees
//  with the selected label) strands the user on a screen they cannot navigate
//  back to.
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

    // MARK: - The two default factories agree

    /// `FunctionCallType.getDefault` drives the dropdown label and
    /// `FunctionCallInstance.getDefault` builds the form body. They are separate
    /// switches over the same chain, so nothing but a test keeps them in step.
    ///
    /// Coverage gap, deliberate: the sweep uses each chain's *native* ticker,
    /// so THORChain is represented by RUNE. THORChain is also the only chain
    /// whose default is ticker-dependent, and the two factories spell that
    /// condition differently — a substring match on one side, an equality on
    /// the other — so the TCY-family tickers are not covered here. Extending
    /// the sweep to them is a follow-up, not this change.
    ///
    /// A chain whose entry resolves to `.action` (exactly one operation,
    /// already migrated) never renders the dropdown `FunctionCallInstance
    /// .getDefault` builds a form for — the passthrough opens the migrated
    /// screen directly, bypassing both factories. dYdX is the first such
    /// chain (see `FunctionCallMigrationSeamTests
    /// .testASingleActionChainMayDefaultToItsOnlyMigratedOperation`), so it is
    /// exempt from the agreement this test otherwise requires.
    func testBothDefaultFactoriesAgreeForEveryMemoChain() {
        for chain in CoinAction.memoChains {
            let coin = nativeCoin(for: chain)
            guard case .list = FunctionActionCatalog.entry(for: coin) else { continue }
            assertDefaultFactoriesAgree(for: coin)
        }
    }

    // MARK: - Helpers

    /// Asserts the selected dropdown entry and the built form describe the same
    /// function for `coin`.
    private func assertDefaultFactoriesAgree(
        for coin: Coin,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let selected = FunctionCallType.getDefault(for: coin)
        let built = FunctionCallInstance.getDefault(for: coin, vault: vault)
        XCTAssertEqual(
            functionCallType(of: built),
            selected,
            "\(coin.chain)/\(coin.ticker): dropdown opens on \(selected) but the form is \(built)",
            file: file,
            line: line
        )
    }

    /// The function each sub-model case represents. Exhaustive by construction:
    /// a new `FunctionCallInstance` case fails to compile until it is mapped.
    private func functionCallType(of instance: FunctionCallInstance) -> FunctionCallType {
        switch instance {
        case .custom: return .custom
        case .addThorLP: return .addThorLP
        }
    }

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
