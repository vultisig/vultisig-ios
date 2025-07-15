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
    @Published var isLoadingEVMTokens: Bool = false
    @Published var isLoadingSolanaTokens: Bool = false
    @Published var error: Error?
    
    private let oneInchservice = OneInchService.shared
    private var loadingTask: Task<Void, Never>?
    
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
    
    func preExistingTokens(groupedChain: GroupedChain) ->[CoinMeta] {
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
        case let error as Errors:
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
        loadOtherTokens(chain: groupedChain.chain)
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
        isLoadingEVMTokens = false
        isLoadingSolanaTokens = false
    }
    
    private func loadExternalTokens(groupedChain: GroupedChain) async {
        guard !Task.isCancelled else { return }
        
        isLoading = true
        
        switch groupedChain.chain.chainType {
        case .EVM:
            await loadTokens(for: groupedChain.chain, type: .evm)
        case .Solana:
            await loadTokens(for: groupedChain.chain, type: .solana)
        default:
            break
        }
        
        // Update selected and preExist tokens after loading external tokens
        if !Task.isCancelled {
            selectedTokens = selectedTokens(groupedChain: groupedChain)
            preExistTokens = preExistingTokens(groupedChain: groupedChain)
        }
        
        isLoading = false
    }
}

private extension TokenSelectionViewModel {
    
    enum Errors: Error, LocalizedError {
        case noTokens
        case networkError
        case rateLimitExceeded
        
        var errorDescription: String? {
            switch self {
            case .noTokens:
                return "Tokens not found"
            case .networkError:
                return "Unable to connect.\nPlease check your internet connection and try again"
            case .rateLimitExceeded:
                return "Too many requests.\nPlease close this screen and try again later"
            }
        }
    }
    
    enum TokenLoadingType {
        case evm
        case solana
    }
    
    func loadTokens(for chain: Chain, type: TokenLoadingType) async {
        guard !Task.isCancelled else { return }
        
        // Set chain-specific loading flag
        setLoadingFlag(for: type, isLoading: true)
        
        do {
            let newTokens = try await fetchTokens(for: chain, type: type)
            
            guard !Task.isCancelled else { return }
            
            // Filter out duplicates
            let uniqueTokens = newTokens.filter { item in
                !tokens.contains { $0.ticker == item.ticker }
            }
            
            tokens.append(contentsOf: uniqueTokens)
            
        } catch let error as NSError {
            if !Task.isCancelled {
                // Check for rate limit error (429)
                if error.code == 429 {
                    self.error = Errors.rateLimitExceeded
                } else {
                    self.error = Errors.networkError
                }
            }
        } catch {
            if !Task.isCancelled {
                self.error = Errors.networkError
            }
        }
        
        // Reset chain-specific loading flag
        setLoadingFlag(for: type, isLoading: false)
    }
    
    func fetchTokens(for chain: Chain, type: TokenLoadingType) async throws -> [CoinMeta] {
        switch type {
        case .evm:
            if oneInchservice.isChainSupported(chain: chain) == false {
                return []
            }
            guard let chainID = chain.chainID else { return [] }
            let oneInchTokens = try await oneInchservice.fetchTokens(chain: chainID)
                .sorted(by: { $0.name < $1.name })
                .map { $0.toCoinMeta(chain: chain) }
            return oneInchTokens
            
        case .solana:
            let jupTokens = try await SolanaService.shared.fetchSolanaJupiterTokenList()
            return jupTokens
        }
    }
    
    func setLoadingFlag(for type: TokenLoadingType, isLoading: Bool) {
        switch type {
        case .evm:
            isLoadingEVMTokens = isLoading
        case .solana:
            isLoadingSolanaTokens = isLoading
        }
    }
    
    func loadOtherTokens(chain: Chain) {
        tokens = TokensStore.TokenSelectionAssets
            .filter { $0.chain == chain && !$0.isNativeToken }
    }
}
