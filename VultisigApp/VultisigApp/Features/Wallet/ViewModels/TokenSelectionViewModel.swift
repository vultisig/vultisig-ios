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

    func loadData(chain: Chain, vault: Vault) {
        // Cancel any existing loading task
        loadingTask?.cancel()

        // Reset error state
        error = nil

        // Load basic tokens immediately (synchronous)
        let hiddenTokens = vault.hiddenTokens
        let chainCoins = vault.coins(for: chain)
        selectedTokens = logic.selectedTokens(chainCoins: chainCoins, tokens: tokens)
        preExistTokens = logic.preExistingTokens(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)

        // Start async loading of external tokens
        loadingTask = Task { [weak self] in
            guard let self else { return }
            await self.loadExternalTokens(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)
        }
    }

    func cancelLoading() {
        loadingTask?.cancel()
        isLoading = false
    }

    func updateSearchedTokens(chain: Chain, vault: Vault) {
        let chainCoins = vault.coins(for: chain)
        searchedTokens = logic.filteredTokens(chainCoins: chainCoins, searchText: searchText, tokens: tokens)
    }

    private func loadExternalTokens(chain: Chain, chainCoins: [Coin], hiddenTokens: [HiddenToken]) async {
        guard !Task.isCancelled else { return }

        isLoading = true
        error = nil

        do {
            let result = try await logic.loadExternalTokens(
                chain: chain,
                chainCoins: chainCoins,
                currentTokens: tokens,
                hiddenTokens: hiddenTokens
            )

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

    func selectedTokens(chainCoins: [Coin], tokens: [CoinMeta]) -> [CoinMeta] {
        let tickers = chainCoins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }

        let filteredTokens = tokens.filter { token in
            tickers.contains(token.ticker.lowercased())
        }
        // Convert tickers to tokens if they are not already in the existing tokens list
        let tickerTokens = chainCoins.filter { coin in
            tickers.contains(coin.ticker.lowercased()) &&
            !tokens.contains { token in token.ticker.lowercased() == coin.ticker.lowercased() }
        }.map { coin in
            coin.toCoinMeta()
        }

        return (filteredTokens + tickerTokens).uniqueBy { $0.uniqueId }
    }

    func preExistingTokens(chain: Chain, chainCoins: [Coin], hiddenTokens: [HiddenToken]) -> [CoinMeta] {
        let tickers = chainCoins
            .filter { !$0.isNativeToken }
            .map { $0.ticker.lowercased() }

        return TokensStore.TokenSelectionAssets
            .filter { token in
                token.chain == chain &&
                !token.isNativeToken &&
                !tickers.contains(token.ticker.lowercased()) &&
                !hiddenTokens.contains { $0.matches(token) }
            }
    }

    func filteredTokens(chainCoins: [Coin], searchText: String, tokens: [CoinMeta]) -> [CoinMeta] {
        guard !searchText.isEmpty else {
            return []
        }

        let tickers = chainCoins
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

    func loadExternalTokens(
        chain: Chain,
        chainCoins: [Coin],
        currentTokens: [CoinMeta],
        hiddenTokens: [HiddenToken]
    ) async throws -> LoadResult {
        let currentTokenIdentifiers = Set(currentTokens.map { "\($0.chain.rawValue):\($0.ticker)" })

        // Propagate errors instead of swallowing them with try?
        let newTokens = try await searchService.loadTokens(for: chain)
        let uniqueTokens = newTokens.filter { !currentTokenIdentifiers.contains("\($0.chain.rawValue):\($0.ticker)") }

        let allTokens = currentTokens + uniqueTokens
        let updatedSelectedTokens = selectedTokens(chainCoins: chainCoins, tokens: allTokens)
        let updatedPreExistTokens = preExistingTokens(chain: chain, chainCoins: chainCoins, hiddenTokens: hiddenTokens)

        return LoadResult(
            newTokens: uniqueTokens,
            updatedSelectedTokens: updatedSelectedTokens,
            updatedPreExistTokens: updatedPreExistTokens
        )
    }
}
