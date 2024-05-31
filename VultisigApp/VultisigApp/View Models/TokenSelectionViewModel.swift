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
    @Published var error: Error?

    private let oneInchservice = OneInchService.shared

    var filteredTokens: [OneInchToken] {
        guard !searchText.isEmpty else { return tokens }
        return tokens.filter { meal in
            meal.name.lowercased().contains(searchText.lowercased()) ||
            meal.symbol.lowercased().contains(searchText.lowercased())
        }
    }

    var showRetry: Bool {
        switch error {
        case let error as Errors:
            return error == .networkError
        default:
            return false
        }
    }

    func loadData(chain: Chain) async {
        guard let chainID = chain.chainID else { return }
        isLoading = true
        do {
            tokens = try await oneInchservice.fetchTokens(chain: chainID).sorted(by: { $0.name < $1.name })
            if tokens.isEmpty {
                self.error = Errors.noTokens
            }
        } catch {
            self.error = Errors.networkError
        }
        isLoading = false
    }
}

private extension TokenSelectionViewModel {

    enum Errors: Error, LocalizedError {
        case noTokens
        case networkError

        var errorDescription: String? {
            switch self {
            case .noTokens:
                return "Tokens not found"
            case .networkError:
                return "Unable to connect.\nPlease check your internet connection and try again"
            }
        }
    }
}
