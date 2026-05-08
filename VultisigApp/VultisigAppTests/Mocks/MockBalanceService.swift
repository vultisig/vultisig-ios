//
//  MockBalanceService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

// swiftlint:disable async_without_await

final class MockBalanceService: BalanceServiceProtocol, @unchecked Sendable {
    private(set) var updateBalanceCallCount = 0
    private(set) var lastUpdatedCoin: Coin?

    func updateBalance(for coin: Coin) async {
        updateBalanceCallCount += 1
        lastUpdatedCoin = coin
    }
}

// swiftlint:enable async_without_await
