//
//  MockBlockChainService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

// swiftlint:disable async_without_await

final class MockBlockChainService: BlockChainServiceProtocol, @unchecked Sendable {
    var stubbedResult: Result<BlockChainSpecific, Error>
    private(set) var fetchSwapCallCount = 0
    private(set) var lastDraft: SwapDraft?

    init(stubbedResult: Result<BlockChainSpecific, Error>) {
        self.stubbedResult = stubbedResult
    }

    func fetchSwapBlockChainSpecific(draft: SwapDraft) async throws -> BlockChainSpecific {
        fetchSwapCallCount += 1
        lastDraft = draft
        return try stubbedResult.get()
    }
}

// swiftlint:enable async_without_await
