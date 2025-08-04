//
//  TokenSelectionViewModel.swift
//  VultisigApp
//

import SwiftUI

@MainActor
class TokenSelectionViewModel: ObservableObject {
    
    @Published var searchText: String = .empty
    @Published var tokens: [CoinMeta] = []
    @Published var selectedTokens: [CoinMeta] = []
    @Published var preExistTokens: [CoinMeta] = []
    @Published var searchedTokens: [CoinMeta] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?
    private var loadingTask: Task<Void, Never>?
    
    private let searchService = TokenSearchService()
    
    func selectedTokens(groupedChain: GroupedChain) -> [CoinMeta] {
        let tickers = groupedChain.coins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }
        
        let filteredTokens = tokens.filter { token in
            tickers.contains(token.ticker.lowercased())
        }
        // Convert tickers to tokens if they are not already in the existing tokens list
        let tickerTokens = groupedChain.coins.filter { coin in
            tickers.contains(coin.ticker.lowercased()) &&
            !tokens.contains { token in token.ticker.lowercased() == coin.ticker.lowercased() }
        }.map { coin in
            coin.toCoinMeta()
        }
        
        return filteredTokens + tickerTokens
    }
    
    func preExistingTokens(groupedChain: GroupedChain) -> [CoinMeta] {
        let tickers = groupedChain.coins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }
        
        return TokensStore.TokenSelectionAssets
            .filter { $0.chain == groupedChain.chain && !$0.isNativeToken && !tickers.contains($0.ticker.lowercased())}
    }
    
    func updateSearchedTokens(groupedChain: GroupedChain) {
        searchedTokens = filteredTokens(groupedChain: groupedChain)
    }
    
    func filteredTokens(groupedChain: GroupedChain) -> [CoinMeta] {
        guard !searchText.isEmpty else {
            return []
        }
        
        let tickers = groupedChain.coins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }
        
        let filtered = tokens
            .filter {
                $0.ticker.lowercased().contains(searchText.lowercased()) && !tickers.contains($0.ticker.lowercased()) }
            .prefix(20)
        
        return Array(filtered)
    }
    
    var showRetry: Bool {
        switch error {
        case let error as TokenSearchServiceError:
            return error == .networkError
        default:
            return false
        }
    }
    
    func loadData(groupedChain: GroupedChain) {
        // Cancel any existing loading task
        loadingTask?.cancel()
        
        // Reset error state
        error = nil
        
        // Load basic tokens immediately (synchronous)
        selectedTokens = selectedTokens(groupedChain: groupedChain)
        preExistTokens = preExistingTokens(groupedChain: groupedChain)
        
        // Start async loading of external tokens
        loadingTask = Task {
            await loadExternalTokens(groupedChain: groupedChain)
        }
    }
    
    func cancelLoading() {
        loadingTask?.cancel()
        isLoading = false
    }
    
    private func loadExternalTokens(groupedChain: GroupedChain) async {
        guard !Task.isCancelled else { return }
        
        isLoading = true
        
        let currentTokenIdentifiers = Set(tokens.map { "\($0.chain.rawValue):\($0.ticker)" })
        let newTokens = (try? await searchService.loadTokens(for: groupedChain.chain)) ?? []
        let uniqueTokens = newTokens.filter { !currentTokenIdentifiers.contains("\($0.chain.rawValue):\($0.ticker)") }
        tokens.append(contentsOf: uniqueTokens)
        
        // Update selected and preExist tokens after loading external tokens
        if !Task.isCancelled {
            selectedTokens = selectedTokens(groupedChain: groupedChain)
            preExistTokens = preExistingTokens(groupedChain: groupedChain)
        }
        
        isLoading = false
    }
}
