//
//  MockBalanceService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

// swiftlint:disable async_without_await

final class MockBalanceService: BalanceServiceProtocol {
    private(set) var updateBalanceCallCount = 0
    private(set) var lastUpdatedCoin: Coin?

    /// Reports that a live balance landed — the stub always "succeeds".
    @discardableResult
    func updateBalance(for coin: Coin) async -> Bool {
        updateBalanceCallCount += 1
        lastUpdatedCoin = coin
        return true
    }
}

// swiftlint:enable async_without_await
