//
//  TokenSelectionViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.05.2024.
//

import SwiftUI

@MainActor
class TokenSelectionViewModel: ObservableObject {

    @Published var searchText: String = .empty
    @Published var tokens: [OneInchToken] = []
    @Published var isLoading: Bool = false

    private let oneInchservice = OneInchService.shared

    var filteredTokens: [OneInchToken] {
        guard !searchText.isEmpty else { return tokens }
        return tokens.filter { meal in
            meal.name.lowercased().contains(searchText.lowercased()) ||
            meal.symbol.lowercased().contains(searchText.lowercased())
        }
    }

    func loadData(chain: Chain) async throws {
        guard let chainID = chain.chainID else { return }
        isLoading = true
        tokens = try await oneInchservice.fetchTokens(chain: chainID).sorted(by: { $0.name < $1.name })
        isLoading = false
    }
}
