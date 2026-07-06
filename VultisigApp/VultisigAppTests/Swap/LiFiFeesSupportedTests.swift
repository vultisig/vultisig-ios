//
//  LiFiFeesSupportedTests.swift
//  VultisigAppTests
//
//  Pins `Coin.isLifiFeesSupported`, the gate that decides whether the
//  `integrator`/`fee` params are sent on a LI.FI quote. The VULT-discounted
//  affiliate fee must be charged on EVM **and** Solana routes; non-LI.FI
//  source chains stay excluded. Solana was previously omitted because LI.FI
//  rejected the fee params on those routes — that limitation no longer applies,
//  so a Solana source must now opt in like EVM.
//

import XCTest
@testable import VultisigApp

final class LiFiFeesSupportedTests: XCTestCase {

    func testEVMSourcesChargeFee() {
        // Sanity baseline: classic EVM plus the two non-obvious EVM chains that
        // also route through LI.FI (Cronos, Hyperliquid) all charge the fee.
        for chain in [Chain.ethereum, .arbitrum, .base, .cronosChain, .hyperliquid] {
            XCTAssertTrue(makeCoin(chain).isLifiFeesSupported, "\(chain) is EVM and must charge the LI.FI fee")
        }
    }

    func testSolanaSourceChargesFee() {
        // The fix: Solana LI.FI routes now charge the same VULT-discounted
        // affiliate fee as EVM, instead of displaying a fee that was never sent.
        XCTAssertTrue(makeCoin(.solana).isLifiFeesSupported, "Solana must charge the LI.FI fee")
    }

    func testNonLiFiSourcesDoNotChargeFee() {
        for chain in [Chain.bitcoin, .thorChain, .ton, .cardano] {
            XCTAssertFalse(makeCoin(chain).isLifiFeesSupported, "\(chain) must not charge a LI.FI fee")
        }
    }

    private func makeCoin(_ chain: Chain) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: chain.ticker, decimals: 18, isNativeToken: true)
        return Coin(asset: asset, address: "test-address", hexPublicKey: "")
    }
}
