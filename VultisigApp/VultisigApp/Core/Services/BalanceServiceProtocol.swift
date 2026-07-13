//
//  BalanceServiceProtocol.swift
//  VultisigApp
//
//  Test seam over `BalanceService`. Production singleton `BalanceService.shared`
//  continues to be the live wiring; injecting the protocol lets tests stub out
//  balance refreshes without touching the network or SwiftData.
//

import Foundation

protocol BalanceServiceProtocol {
    func updateBalance(for coin: Coin) async
    /// Fail-closed refresh — throws if the live balance fetch fails. See
    /// `BalanceService.refreshSpendableBalanceOrThrow`.
    func refreshSpendableBalanceOrThrow(for coin: Coin) async throws
}

extension BalanceServiceProtocol {
    /// Default for test seams: best-effort refresh that never throws. The live
    /// `BalanceService` overrides this with the fail-closed implementation.
    func refreshSpendableBalanceOrThrow(for coin: Coin) async throws {
        await updateBalance(for: coin)
    }
}

extension BalanceService: BalanceServiceProtocol {}
