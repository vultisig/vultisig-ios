//
//  BlockChainServiceSuiCacheTests.swift
//  VultisigAppTests
//
//  Ensures Sui chain-specific payloads are not reused across send amounts.
//

@testable import VultisigApp
import XCTest

final class BlockChainServiceSuiCacheTests: XCTestCase {
    func testSuiBlockSpecificIsNotCacheableBecauseItEmbedsAmountBoundCoinSelection() {
        XCTAssertFalse(BlockChainService.allowsBlockSpecificCache(for: .sui))
    }

    func testSolanaBlockSpecificRemainsNotCacheableBecauseBlockhashExpires() {
        XCTAssertFalse(BlockChainService.allowsBlockSpecificCache(for: .solana))
    }
}
