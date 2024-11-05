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
        case coin(CoinMeta)
        case oneInch(OneInchToken)
        
        var symbol: String {
            switch self {
            case .coin(let coin):
                return coin.ticker
            case .oneInch(let coin):
                return coin.symbol
            }
        }
        
        var logo: String {
            switch self {
            case .coin(let coin):
                return coin.logo
            case .oneInch(let token):
                return token.logoUrl?.description ?? .empty
            }
        }

        func asset(chain: Chain) -> CoinMeta {
            switch self {
            case .coin(let asset):
                return asset
            case .oneInch(let token):
                return token.toCoinMeta(chain: chain)
            }
        }
    }
    
    @Published var searchText: String = .empty
    @Published var tokens: [CoinMeta] = []
    @Published var selectedTokens: [Token] = []
    @Published var preExistTokens: [Token] = []
    @Published var searchedTokens: [Token] = []
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
            Token.coin(coin.toCoinMeta())
        }

        return filteredTokens + tickerTokens
    }
    
    func preExistingTokens(groupedChain: GroupedChain) ->[Token] {
        let tickers = groupedChain.coins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }
        
        return TokensStore.TokenSelectionAssets
            .filter { $0.chain == groupedChain.chain && !$0.isNativeToken && !tickers.contains($0.ticker.lowercased())}
            .map { .coin($0) }
    }
    func updateSearchedTokens(groupedChain: GroupedChain) {
        searchedTokens = filteredTokens(groupedChain: groupedChain)
    }

    func filteredTokens(groupedChain: GroupedChain) -> [Token] {
        guard !searchText.isEmpty else { return [] }
        let tickers = groupedChain.coins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }
        return tokens
            .filter { $0.symbol.lowercased().contains(searchText.lowercased()) && !tickers.contains($0.symbol.lowercased())}
            
    }
    
    var showRetry: Bool {
        switch error {
        case let error as Errors:
            return error == .networkError
        default:
            return false
        }
    }
    
    func loadData(groupedChain: GroupedChain) async {
        error = nil
        // always keep those tokens in vultisig tokenstore
        await loadOtherTokens(chain: groupedChain.chain)
        
        if groupedChain.chain.chainType == .EVM {
            await loadEVMTokens(chain: groupedChain.chain)
        }
        selectedTokens = selectedTokens(groupedChain: groupedChain)
        preExistTokens = preExistingTokens(groupedChain: groupedChain)
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
            let oneInchTokens: [Token] = response.map { .oneInch($0) }
            let uniqueTokens = oneInchTokens.filter { item in
                !tokens.contains{$0.symbol == item.symbol}
            }
            tokens.append(contentsOf: uniqueTokens)
            
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
