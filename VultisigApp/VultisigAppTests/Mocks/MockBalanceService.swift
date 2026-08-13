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

    /// Whether the stubbed refresh reports that a live balance landed.
    var updateBalanceSucceeds = true

    @discardableResult
    func updateBalance(for coin: Coin) async -> Bool {
        updateBalanceCallCount += 1
        lastUpdatedCoin = coin
        return updateBalanceSucceeds
    }
}

// swiftlint:enable async_without_await
