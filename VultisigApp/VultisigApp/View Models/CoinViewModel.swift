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

    private let balanceService = BalanceService()

    func loadData(coin: Coin) async {
        isLoading = true

        do {
            try await balanceService.balance(for: coin)
        }
        catch {
            print("error fetching data: \(error.localizedDescription)")
        }

        isLoading = false
    }
}
