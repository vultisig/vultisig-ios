//
//  CircleViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/12/25.
//

import Foundation

// MARK: - View Model (State Only)
final class CircleViewModel: ObservableObject, Hashable, Equatable {
    static func == (lhs: CircleViewModel, rhs: CircleViewModel) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    private let id = UUID()
    @Published var isLoading = false
    @Published var error: Error?
    @Published var missingEth = false
    @Published var balance: Decimal = .zero
    @Published var ethBalance: Decimal = .zero
    @Published var apy: String = "0%"
    @Published var totalRewards: String = "0"
    @Published var currentRewards: String = "0"
    @Published var showDeposit = false
    @Published var showWithdraw = false
    
    let logic = CircleViewLogic()
}
