//
//  TokenMetadataResolver.swift
//  VultisigApp
//
//  Live ERC-20 metadata fallback for unknown contracts during dApp tx display.
//  Used by `JoinKeysignViewModel.resolveTokenDisplay(...)` after vault + TokensStore
//  lookups miss. Caches per (chain, contractAddress) for 24h since ERC-20 symbol /
//  decimals are immutable on-chain. Single-flights concurrent resolves of the same
//  pair so the keysign UI never fires duplicate `eth_call`s.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "token-metadata-resolver")

/// Successful metadata lookup. Empty `symbol` is treated as a failure and not cached.
struct TokenMetadata: Equatable, Sendable {
    let symbol: String
    let decimals: Int
}

/// Closure-based fetcher so tests can inject a deterministic fake without mocking
/// SwiftData or the HTTP stack. The production default uses `RpcEvmService.getTokenInfo`.
typealias TokenMetadataFetcher = @Sendable (_ chain: Chain, _ contractAddress: String) async throws -> TokenMetadata

actor TokenMetadataResolver {
    static let shared = TokenMetadataResolver()

    private struct CachedEntry {
        let metadata: TokenMetadata
        let fetchedAt: Date
    }

    private var cache: [String: CachedEntry] = [:]
    private var inFlight: [String: Task<TokenMetadata?, Never>] = [:]

    private let ttl: TimeInterval
    private let fetcher: TokenMetadataFetcher
    private let now: @Sendable () -> Date

    init(
        ttl: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        fetcher: @escaping TokenMetadataFetcher = TokenMetadataResolver.defaultFetcher
    ) {
        self.ttl = ttl
        self.now = now
        self.fetcher = fetcher
    }

    /// Returns cached metadata if fresh, otherwise fetches via the configured fetcher.
    /// Returns `nil` on any failure (network error, non-ERC-20 contract, empty symbol).
    /// Concurrent calls for the same key are deduplicated via in-flight task tracking.
    func resolve(contractAddress: String, on chain: Chain) async -> TokenMetadata? {
        let key = cacheKey(chain: chain, contractAddress: contractAddress)

        if let cached = cache[key], now().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.metadata
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<TokenMetadata?, Never> { [fetcher, chain, contractAddress] in
            do {
                let metadata = try await fetcher(chain, contractAddress)
                // `RpcEvmService.getTokenInfo` swallows errors and returns empty strings
                // — treat that as a failed lookup so we don't cache garbage. Also bound
                // `decimals` to a sane range: the contract is untrusted, and downstream
                // formatting computes `BigInt(10).power(decimals)`. A malicious or
                // misbehaving contract returning e.g. 65535 would chew CPU during render.
                // 36 is well above any legitimate token (18 is the de-facto ceiling).
                guard !metadata.symbol.isEmpty,
                      (0...36).contains(metadata.decimals) else {
                    return nil
                }
                return metadata
            } catch {
                logger.warning("Token metadata fetch failed for chain=\(chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }
        inFlight[key] = task

        let result = await task.value
        inFlight.removeValue(forKey: key)
        if let result {
            cache[key] = CachedEntry(metadata: result, fetchedAt: now())
        }
        return result
    }

    private func cacheKey(chain: Chain, contractAddress: String) -> String {
        "\(chain.rawValue)|\(contractAddress.lowercased())"
    }

    private static let defaultFetcher: TokenMetadataFetcher = { chain, contractAddress in
        guard let config = try? EvmServiceConfig.getConfig(forChain: chain) else {
            throw TokenMetadataResolverError.unsupportedChain(chain)
        }
        let service = RpcEvmService(config.rpcEndpoint)
        let info = try await service.getTokenInfo(contractAddress: contractAddress)
        return TokenMetadata(symbol: info.symbol, decimals: info.decimals)
    }
}

enum TokenMetadataResolverError: Error, Equatable {
    case unsupportedChain(Chain)
}
