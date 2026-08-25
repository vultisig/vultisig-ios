//
//  BlockaidChainIdentifierTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class BlockaidChainIdentifierTests: XCTestCase {
    func testHyperEvmUsesBlockaidHyperevmIdentifier() {
        XCTAssertEqual(
            BlockaidChainIdentifier.name(for: .hyperliquid),
            "hyperevm"
        )
    }

    func testRobinhoodHasNoBlockaidIdentifier() {
        XCTAssertNil(BlockaidChainIdentifier.name(for: .robinhood))
    }

    func testScannerSupportsHyperEvmButNotRobinhood() {
        let scanner = BlockaidScannerService(
            blockaidRpcClient: MockBlockaidRpcClient()
        )
        let supported = scanner.getSupportedChains()[.scanTransaction] ?? []

        XCTAssertTrue(supported.contains(.hyperliquid))
        XCTAssertFalse(supported.contains(.robinhood))
    }
}
