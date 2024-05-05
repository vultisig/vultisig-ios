//
//  CoinViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation
import SwiftUI
import BigInt

@MainActor
class CoinViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var balanceFiat: String? = nil
    @Published var coinBalance: String? = nil
    
    private let balanceService = BalanceService()

    func loadData(coin: Coin) async {
        isLoading = true

        do {
            let balance = try await balanceService.balance(for: coin)
            coinBalance = balance.coinBalance
            balanceFiat = balance.balanceFiat
        }
        catch {
            print("error fetching data: \(error.localizedDescription)")
        }

        isLoading = false
    }
}
