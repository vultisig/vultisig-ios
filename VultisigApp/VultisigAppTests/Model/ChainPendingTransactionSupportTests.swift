//
//  ChainPendingTransactionSupportTests.swift
//  VultisigApp
//
//  Pins the per-chain values of `Chain.supportsPendingTransactions` and
//  `Chain.supportsEip1559` after both were rewritten to remove misleading /
//  risky `default:` branches:
//
//  - `supportsPendingTransactions` is now an exhaustive switch (no `default:`)
//    so a newly added nonce/Cosmos-style chain cannot silently inherit
//    `false` and serve a stale nonce from cache. These asserts lock the
//    true/false split so the exhaustive rewrite stayed byte-identical.
//  - `supportsEip1559` collapsed a dead explicit allow-list into
//    `self != .bscChain`; the assert pins that BSC is the only chain without
//    EIP-1559 fee markets.
//

@testable import VultisigApp
import XCTest

final class ChainPendingTransactionSupportTests: XCTestCase {

    // MARK: - supportsPendingTransactions

    /// The nonce/sequence-tracking chains that MUST report `true`.
    /// Preserved exactly from the pre-refactor allow-list.
    private let pendingTrueChains: [Chain] = [
        .thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain,
        .gaiaChain, .kujira, .osmosis, .dydx, .terra, .terraClassic,
        .noble, .akash, .qbtc
    ]

    func testPendingTransactionsTrueForNonceChains() {
        for chain in pendingTrueChains {
            XCTAssertTrue(
                chain.supportsPendingTransactions,
                "\(chain) must support pending-transaction tracking (nonce/sequence)."
            )
        }
    }

    func testPendingTransactionsFalseForRepresentativeChains() {
        // A representative sample across UTXO / EVM / other families that
        // must remain `false` after the exhaustive rewrite.
        let falseChains: [Chain] = [
            .bitcoin, .ethereum, .solana, .bscChain, .sui, .ripple,
            .cardano, .polkadot, .ton, .tron
        ]
        for chain in falseChains {
            XCTAssertFalse(
                chain.supportsPendingTransactions,
                "\(chain) must NOT report pending-transaction support."
            )
        }
    }

    /// Belt-and-braces: exactly the allow-list chains (and no others) are
    /// `true`, so a future edit that widens the `true` branch is caught even
    /// for chains this file doesn't enumerate explicitly.
    func testPendingTransactionsTrueSetIsExactlyTheAllowList() {
        let actualTrue = Set(Chain.allCases.filter { $0.supportsPendingTransactions })
        XCTAssertEqual(actualTrue, Set(pendingTrueChains))
    }

    // MARK: - supportsEip1559

    func testEip1559FalseOnlyForBsc() {
        for chain in Chain.allCases {
            let expected = chain != .bscChain
            XCTAssertEqual(
                chain.supportsEip1559,
                expected,
                "\(chain).supportsEip1559 should be \(expected); BSC is the only chain without EIP-1559."
            )
        }
    }

    func testBscDoesNotSupportEip1559() {
        XCTAssertFalse(Chain.bscChain.supportsEip1559)
    }
}
