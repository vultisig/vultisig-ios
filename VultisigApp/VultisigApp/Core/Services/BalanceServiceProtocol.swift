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
}

extension BalanceService: BalanceServiceProtocol {}
