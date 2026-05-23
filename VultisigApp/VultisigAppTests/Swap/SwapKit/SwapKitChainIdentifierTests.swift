//
//  SwapKitChainIdentifierTests.swift
//  VultisigAppTests
//
//  Pin the chainId-string mapping to the canonical chain table documented in
//  `swapkit-spike/api-contract.md`. SwapKit's `/track` endpoint rejects any
//  other value — these assertions are the iOS-side guard against typos.
//

import XCTest
@testable import VultisigApp

final class SwapKitChainIdentifierTests: XCTestCase {

    func testEVMChainsReturnNumericChainIds() {
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .ethereum), "1")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .arbitrum), "42161")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .avalanche), "43114")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .base), "8453")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .bscChain), "56")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .polygon), "137")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .polygonV2), "137")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .optimism), "10")
    }

    func testTronUsesNumericChainIdNotName() {
        // The docs sometimes show `TRX` for tron — `/track` requires the
        // numeric chainId, which is what the SDK actually accepts.
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .tron), "728126428")
    }

    func testNonEVMChainsReturnSlugs() {
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .bitcoin), "bitcoin")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .solana), "solana")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .litecoin), "litecoin")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .dogecoin), "dogecoin")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .ripple), "ripple")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .ton), "ton")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .cardano), "cardano")
        XCTAssertEqual(SwapKitChainIdentifier.chainId(for: .gaiaChain), "cosmoshub-4")
    }

    func testUnsupportedChainsReturnNil() {
        // Chains we don't route through SwapKit — the polling code surfaces
        // the explorer link instead of attempting an invalid `/track` call.
        XCTAssertNil(SwapKitChainIdentifier.chainId(for: .polkadot))
        XCTAssertNil(SwapKitChainIdentifier.chainId(for: .akash))
    }
}
