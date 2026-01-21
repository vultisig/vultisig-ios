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

    private let logic = TokenSelectionLogic.shared

    var showRetry: Bool {
        return logic.showRetry(error: error)
    }

    func loadData(groupedChain: GroupedChain) {
        // Cancel any existing loading task
        loadingTask?.cancel()

        // Reset error state
        error = nil

        // Load basic tokens immediately (synchronous)
        selectedTokens = logic.selectedTokens(groupedChain: groupedChain, tokens: tokens)
        preExistTokens = logic.preExistingTokens(groupedChain: groupedChain)

        // Start async loading of external tokens
        loadingTask = Task { [weak self] in
            guard let self else { return }
            await self.loadExternalTokens(groupedChain: groupedChain)
        }
    }

    func cancelLoading() {
        loadingTask?.cancel()
        isLoading = false
    }

    func updateSearchedTokens(groupedChain: GroupedChain) {
        searchedTokens = logic.filteredTokens(groupedChain: groupedChain, searchText: searchText, tokens: tokens)
    }

    private func loadExternalTokens(groupedChain: GroupedChain) async {
        guard !Task.isCancelled else { return }

        isLoading = true
        error = nil

        do {
            let result = try await logic.loadExternalTokens(groupedChain: groupedChain, currentTokens: tokens)

            if !Task.isCancelled {
                tokens.append(contentsOf: result.newTokens)
                selectedTokens = result.updatedSelectedTokens
                preExistTokens = result.updatedPreExistTokens
            }
        } catch {
            // Capture the error for UI display
            self.error = error
        }

        isLoading = false
    }
}

// MARK: - TokenSelectionLogic

struct TokenSelectionLogic {
    static let shared = TokenSelectionLogic()

    private let searchService = TokenSearchService.shared

    private init() {}

    func selectedTokens(groupedChain: GroupedChain, tokens: [CoinMeta]) -> [CoinMeta] {
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

    func filteredTokens(groupedChain: GroupedChain, searchText: String, tokens: [CoinMeta]) -> [CoinMeta] {
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

    func showRetry(error: Error?) -> Bool {
        switch error {
        case let error as TokenSearchServiceError:
            return error == .networkError || error == .rateLimitExceeded
        default:
            return false
        }
    }

    struct LoadResult {
        let newTokens: [CoinMeta]
        let updatedSelectedTokens: [CoinMeta]
        let updatedPreExistTokens: [CoinMeta]
    }

    func loadExternalTokens(groupedChain: GroupedChain, currentTokens: [CoinMeta]) async throws -> LoadResult {
        let currentTokenIdentifiers = Set(currentTokens.map { "\($0.chain.rawValue):\($0.ticker)" })

        // Propagate errors instead of swallowing them with try?
        let newTokens = try await searchService.loadTokens(for: groupedChain.chain)
        let uniqueTokens = newTokens.filter { !currentTokenIdentifiers.contains("\($0.chain.rawValue):\($0.ticker)") }

        let allTokens = currentTokens + uniqueTokens
        let updatedSelectedTokens = selectedTokens(groupedChain: groupedChain, tokens: allTokens)
        let updatedPreExistTokens = preExistingTokens(groupedChain: groupedChain)

        return LoadResult(
            newTokens: uniqueTokens,
            updatedSelectedTokens: updatedSelectedTokens,
            updatedPreExistTokens: updatedPreExistTokens
        )
    }
}
