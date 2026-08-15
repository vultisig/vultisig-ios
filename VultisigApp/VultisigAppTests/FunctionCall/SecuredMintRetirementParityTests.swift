//
//  SecuredMintRetirementParityTests.swift
//  VultisigAppTests
//
//  Pins the contract that makes retiring the legacy SECURE+ mint form safe:
//  every chain that used to reach the mint through the Function screen still
//  reaches it through Swap, and the Function screen those chains keep is
//  internally consistent.
//
//  Three independent tables have to agree for a chain to keep the mint:
//  `Chain.isSwapAvailable` (the Swap button shows), `SecuredAssetCatalog`
//  (the destination picker lists the secured twin even offline), and
//  `SwapCryptoLogic.isSameUnderlyingSecuredMint` (picking that twin routes to
//  the SECURE+ deposit instead of a pool swap). None of them is derived from
//  the others, so a rename in any one silently drops a chain's only remaining
//  route to the operation.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SecuredMintRetirementParityTests: XCTestCase {

    /// The nine L1 chains whose Function screen used to offer the SECURE+ mint
    /// next to `addThorLP`, with the native coin a user holds and the secured
    /// denom that coin mints into.
    ///
    /// THORChain is deliberately absent even though it also lost the arm: a
    /// SECURE+ deposit mints only when an L1 asset lands on a THORChain
    /// inbound, so with a THORChain source the deleted form could only build a
    /// self-addressed deposit that mints nothing. Swap correspondingly never
    /// classifies a THORChain source as a same-underlying mint. Nothing to hold
    /// parity with, so nothing to assert here.
    private static let retiredChains: [(chain: Chain, ticker: String, denom: String)] = [
        (.bitcoin, "BTC", "btc-btc"),
        (.bitcoinCash, "BCH", "bch-bch"),
        (.litecoin, "LTC", "ltc-ltc"),
        (.dogecoin, "DOGE", "doge-doge"),
        (.ethereum, "ETH", "eth-eth"),
        (.avalanche, "AVAX", "avax-avax"),
        (.bscChain, "BNB", "bsc-bnb"),
        (.base, "ETH", "base-eth"),
        (.ripple, "XRP", "xrp-xrp")
    ]

    // MARK: - Swap covers every chain the deleted form covered

    /// Selecting the secured twin of a held L1 asset must be detected as a
    /// same-underlying mint, on every chain the legacy form served. This is the
    /// decision the whole route hangs off — it flips the synthetic quote, the
    /// `.securedMint` transaction mode, and the interactor's payload branch.
    ///
    /// Scope, deliberately narrow: this covers the *detection* only, against a
    /// destination built through the production mapper. The provider
    /// registration, picker merge, quote and payload legs are covered by
    /// `SecuredAssetTokenProviderTests` / `SecuredMintRoutingTests` and by the
    /// on-device path; nothing here would catch those being unwired.
    func testSwapDetectsTheSecuredMintForEveryRetiredChain() {
        for entry in Self.retiredChains {
            let fromCoin = nativeCoin(chain: entry.chain, ticker: entry.ticker)
            let securedCoin = securedTwin(denom: entry.denom)
            XCTAssertTrue(
                SwapCryptoLogic.isSameUnderlyingSecuredMint(fromCoin: fromCoin, toCoin: securedCoin),
                "\(entry.chain): \(fromCoin.swapAsset) no longer matches secured denom \(entry.denom)"
            )
        }
    }

    /// The mint is only reachable where the Swap action is offered at all.
    ///
    /// `isSwapAvailable` is the chain-level half of that. It is not the whole
    /// answer: `Chain.defaultActions` also drops `.swap` for the regions
    /// `SwapFeatureGate` excludes, and the remote action config can disable it
    /// per chain — neither of which is expressible here.
    func testSwapIsAvailableOnEveryRetiredChain() {
        for entry in Self.retiredChains {
            XCTAssertTrue(
                entry.chain.isSwapAvailable,
                "\(entry.chain) can no longer swap, so it has no route to the SECURE+ mint"
            )
        }
    }

    /// The destination picker falls back to a static denom list when the live
    /// `/securedassets` fetch fails. A chain missing from that list loses its
    /// mint whenever THORNode is unreachable.
    func testOfflineCatalogFallbackCoversEveryRetiredChain() {
        for entry in Self.retiredChains {
            XCTAssertTrue(
                SecuredAssetCatalog.fallbackDenoms.contains(entry.denom),
                "\(entry.chain): \(entry.denom) is missing from the offline secured-asset fallback"
            )
        }
    }

    // MARK: - What the Function screen keeps on those chains

    /// The nine L1 chains are down to a single function. That is the
    /// precondition for routing the button straight through to the operation
    /// instead of via the action list, so it is worth pinning.
    func testRetiredChainsOfferAddThorLPOnly() {
        for entry in Self.retiredChains {
            let coin = nativeCoin(chain: entry.chain, ticker: entry.ticker)
            XCTAssertEqual(
                FunctionCallType.getCases(for: coin), [.addThorLP],
                "\(entry.chain) should offer exactly one function"
            )
            assertDefaultsAgree(for: coin)
        }
    }

    /// THORChain keeps the redemption side (SECURE−) and its other functions;
    /// only the mint arm went away.
    func testThorchainKeepsItsRemainingFunctions() {
        let rune = FunctionCallFixture.makeRUNE()
        XCTAssertEqual(
            FunctionCallType.getCases(for: rune),
            [.rebond, .leave, .merge, .unmerge, .custom, .withdrawSecuredAsset]
        )
        assertDefaultsAgree(for: rune)
    }

    // MARK: - Helpers

    /// Asserts the dropdown's opening selection is one the dropdown lists, and
    /// that the sub-model the screen builds is the same function. The two
    /// default factories are separate switches over the same chain, so nothing
    /// but an assertion keeps them in step.
    private func assertDefaultsAgree(
        for coin: Coin,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let selected = FunctionCallType.getDefault(for: coin)
        XCTAssertTrue(
            FunctionCallType.getCases(for: coin).contains(selected),
            "\(coin.chain) opens on \(selected), which the dropdown does not list",
            file: file,
            line: line
        )
        let built = FunctionCallInstance.getDefault(for: coin, vault: vault)
        XCTAssertEqual(
            functionCallType(of: built),
            selected,
            "\(coin.chain): dropdown opens on \(selected) but the form built is \(built)",
            file: file,
            line: line
        )
    }

    private func functionCallType(of instance: FunctionCallInstance) -> FunctionCallType {
        switch instance {
        case .rebond: return .rebond
        case .custom: return .custom
        case .vote: return .vote
        case .cosmosIBC: return .cosmosIBC
        case .merge: return .merge
        case .unmerge: return .unmerge
        case .theSwitch: return .theSwitch
        case .addThorLP: return .addThorLP
        }
    }

    private func nativeCoin(chain: Chain, ticker: String) -> Coin {
        FunctionCallFixture.makeCoin(chain, ticker: ticker, decimals: 8, isNative: true)
    }

    /// The secured destination exactly as the picker builds it — through the
    /// production mapper, so a change to the denom → `CoinMeta` derivation is
    /// caught here rather than in the field.
    private func securedTwin(denom: String) -> Coin {
        Coin(
            asset: SecuredAssetMapper.coinMeta(forDenom: denom),
            address: FunctionCallFixture.thorAddress,
            hexPublicKey: ""
        )
    }
}
