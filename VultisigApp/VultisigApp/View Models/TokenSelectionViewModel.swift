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
    @Published var tokens: [CoinMeta] = []
    @Published var selectedTokens: [CoinMeta] = []
    @Published var preExistTokens: [CoinMeta] = []
    @Published var searchedTokens: [CoinMeta] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    private let oneInchservice = OneInchService.shared
    
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
    
    func loadData(groupedChain: GroupedChain) async {
        error = nil
        // always keep those tokens in vultisig tokenstore
        await loadOtherTokens(chain: groupedChain.chain)
        
        if groupedChain.chain.chainType == .EVM {
            await loadEVMTokens(chain: groupedChain.chain)
        } else if groupedChain.chain.chainType == .Solana {
            await loadSolanaTokens(chain: groupedChain.chain)
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
            let oneInchTokens = try await oneInchservice.fetchTokens(chain: chainID)
                .sorted(by: { $0.name < $1.name })
                .map { $0.toCoinMeta(chain: chain) }

            let uniqueTokens = oneInchTokens.filter { item in
                !tokens.contains { $0.ticker == item.ticker }
            }

            tokens.append(contentsOf: uniqueTokens)
            
        } catch {
            self.error = Errors.networkError
        }
        
        
        isLoading = false
    }
    
    func loadSolanaTokens(chain: Chain) async {
        isLoading = true
        do {
            let oneInchTokens = try await SolanaService.shared.fetchSolanaJupiterTokenList()
            
            print(oneInchTokens)
            
            let uniqueTokens = oneInchTokens.filter { item in
                !tokens.contains { $0.ticker == item.ticker }
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
    }
}
