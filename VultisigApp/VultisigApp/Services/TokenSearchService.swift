//
//  TokenSearchService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/08/2025.
//

import Foundation

struct TokenSearchService {
    static let shared = TokenSearchService()

    private let oneInchservice = OneInchService.shared

    private init() {}

    func loadTokens(for chain: Chain) async throws -> [CoinMeta] {
        guard !Task.isCancelled else { throw TokenSearchServiceError.cancelled }

        do {
            let externalTokens = try await fetchExternalTokens(for: chain)
            let presetTokens = fetchPresetTokens(for: chain)
            let presetTickers = presetTokens.map { $0.ticker.lowercased() }
            let filtered = externalTokens.filter { !presetTickers.contains($0.ticker.lowercased()) }

            guard !Task.isCancelled else { throw TokenSearchServiceError.cancelled }

            return presetTokens + filtered
        } catch let error as NSError {
            guard !Task.isCancelled else { throw TokenSearchServiceError.cancelled }
            // Check for rate limit error (429)
            if error.code == 429 {
                throw TokenSearchServiceError.rateLimitExceeded
            } else {
                throw TokenSearchServiceError.networkError
            }
        } catch {
            guard !Task.isCancelled else { throw TokenSearchServiceError.cancelled }
            throw TokenSearchServiceError.networkError
        }
    }

    private func fetchExternalTokens(for chain: Chain) async throws -> [CoinMeta] {
        switch chain.chainType {
        case .EVM:
            if oneInchservice.isChainSupported(chain: chain) == false {
                return []
            }
            guard let chainID = chain.chainID else { return [] }
            let oneInchTokens = try await oneInchservice.fetchTokens(chain: chainID)
                .sorted(by: { $0.name < $1.name })
                .map { $0.toCoinMeta(chain: chain) }
            return oneInchTokens

        case .Solana:
            let jupTokens = try await SolanaService.shared.fetchSolanaJupiterTokenList()
            return jupTokens
        default:
            return []
        }
    }

    private func fetchPresetTokens(for chain: Chain) -> [CoinMeta] {
        return TokensStore.TokenSelectionAssets
            .filter { $0.chain == chain && !$0.isNativeToken }
    }
}

enum TokenSearchServiceError: Error, LocalizedError {
    case noTokens
    case networkError
    case rateLimitExceeded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noTokens:
            return "Tokens not found"
        case .networkError:
            return "Unable to connect.\nPlease check your internet connection and try again"
        case .rateLimitExceeded:
            return "Too many requests.\nPlease close this screen and try again later"
        case .cancelled:
            return "Request cancelled"
        }
    }
}
