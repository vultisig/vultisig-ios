//
//  TokenSelectionViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.05.2024.
//

import SwiftUI

@MainActor
class TokenSelectionViewModel: ObservableObject {

    enum Token: Hashable {
        case coin(Coin)
        case oneInch(OneInchToken)

        var symbol: String {
            switch self {
            case .coin(let coin):
                return coin.ticker
            case .oneInch(let coin):
                return coin.symbol
            }
        }

        var logo: ImageView.Source {
            switch self {
            case .coin(let coin):
                return .resource(coin.logo)
            case .oneInch(let token):
                return .remote(token.logoUrl)
            }
        }
    }

    @Published var searchText: String = .empty
    @Published var tokens: [Token] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?

    private let oneInchservice = OneInchService.shared

    func selectedTokens(groupedChain: GroupedChain) -> [Token] {
        let tickers = groupedChain.coins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }

        let filteredTokens = tokens.filter { token in
            tickers.contains(token.symbol.lowercased())
        }

        // Convert tickers to tokens if they are not already in the existing tokens list
        let tickerTokens = groupedChain.coins.filter { coin in
            tickers.contains(coin.ticker.lowercased()) &&
            !tokens.contains { token in token.symbol.lowercased() == coin.ticker.lowercased() }
        }.map { coin in
            Token.coin(coin)
        }

        return filteredTokens + tickerTokens
    }


    func filteredTokens(groupedChain: GroupedChain) -> [Token] {
        guard !searchText.isEmpty else { return [] }
        let tickers = groupedChain.coins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }
        return tokens
            .filter { $0.symbol.lowercased().contains(searchText.lowercased())}
            .filter { token in
                !tickers.contains(token.symbol.lowercased())
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
        error = nil

        switch chain.chainType {
        case .EVM:
            await loadEVMTokens(chain: chain)
        default:
            await loadOtherTokens(chain: chain)
        }
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

    func loadEVMTokens(chain: Chain) async {
        guard let chainID = chain.chainID else { return }
        isLoading = true
        do {
            let response = try await oneInchservice.fetchTokens(chain: chainID).sorted(by: { $0.name < $1.name })
            tokens = response.map { .oneInch($0) }

            if tokens.isEmpty {
                error = Errors.noTokens
            }
        } catch {
            self.error = Errors.networkError
        }
        isLoading = false
    }

    func loadOtherTokens(chain: Chain) async {
        tokens = TokensStore.TokenSelectionAssets
            .filter { $0.chain == chain && !$0.isNativeToken }
            .map { .coin($0) }
    }
}
