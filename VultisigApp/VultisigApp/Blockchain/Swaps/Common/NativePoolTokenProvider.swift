//
//  NativePoolTokenProvider.swift
//  VultisigApp
//
//  Destination-token source for the swap coin picker backed by a native
//  protocol's live `Available` swap pools (THORChain `/thorchain/pools`,
//  MayaChain `/mayachain/pools`). Each pool-id (`CHAIN.TICKER-0xCONTRACT`) is
//  resolved to a curated `TokensStore` `CoinMeta` — the pool feed carries no
//  logo / priceProviderId, so a pool with no curated match is dropped (it
//  could not be rendered or added safely). The picker aggregates this bucket
//  alongside the curated + aggregator lists via `DestinationTokenRegistry`,
//  so a token that only has a native-protocol pool still surfaces.
//
//  Registered once per protocol at app startup (see `VultisigApp.init`). Two
//  instances, keyed by distinct `providerKind`, share this one type.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "native-pool-token-provider")

/// Which native protocol a pool feed belongs to.
enum NativeSwapProtocol {
    case thorchain
    case mayachain
}

@MainActor
final class NativePoolTokenProvider: DestinationTokenProvider {

    let providerKind: String

    private let proto: NativeSwapProtocol
    private let httpClient: HTTPClientProtocol
    private let cacheTTL: TimeInterval = 5 * 60
    private var snapshot: Snapshot?
    private var inFlight: Task<[Chain: DestinationTokenBucket]?, Never>?

    private struct Snapshot {
        let buckets: [Chain: DestinationTokenBucket]
        let fetchedAt: Date
    }

    init(proto: NativeSwapProtocol, httpClient: HTTPClientProtocol = HTTPClient()) {
        self.proto = proto
        self.httpClient = httpClient
        switch proto {
        case .thorchain: self.providerKind = "thorchainPool"
        case .mayachain: self.providerKind = "mayachainPool"
        }
    }

    func tokens(for chain: Chain) async -> DestinationTokenBucket {
        await tokens(for: chain, now: Date())
    }

    /// Date-injectable variant used by tests / TTL-sensitive callers.
    func tokens(for chain: Chain, now: Date) async -> DestinationTokenBucket {
        let buckets = await ensureSnapshot(now: now)
        return buckets?[chain] ?? .empty(chain: chain)
    }

    /// Coalescing fetch — concurrent callers share one in-flight Task. Returns
    /// the cached snapshot when fresh; otherwise refreshes. Fail-open to
    /// last-good on a fetch failure (mirrors `SwapKitTokensCache`).
    private func ensureSnapshot(now: Date) async -> [Chain: DestinationTokenBucket]? {
        if let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < cacheTTL {
            return snapshot.buckets
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { [proto, httpClient] () -> [Chain: DestinationTokenBucket]? in
            await Self.fetchBuckets(proto: proto, httpClient: httpClient)
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if let result {
            snapshot = Snapshot(buckets: result, fetchedAt: now)
        }
        return result ?? snapshot?.buckets
    }

    /// Replace the snapshot — test seam so tests don't stand up a fake
    /// `HTTPClient`.
    func setSnapshot(buckets: [Chain: DestinationTokenBucket], fetchedAt: Date = Date()) {
        snapshot = Snapshot(buckets: buckets, fetchedAt: fetchedAt)
    }

    // MARK: - Fetch + map

    private static func fetchBuckets(
        proto: NativeSwapProtocol,
        httpClient: HTTPClientProtocol
    ) async -> [Chain: DestinationTokenBucket]? {
        do {
            let assetIds: [String]
            switch proto {
            case .thorchain:
                let response = try await httpClient.request(
                    ThorchainMainnetAPI(.pools),
                    responseType: [THORChainPoolResponse].self
                )
                assetIds = response.data.filter { $0.status.caseInsensitiveCompare("Available") == .orderedSame }.map { $0.asset }
            case .mayachain:
                let response = try await httpClient.request(
                    MayaChainAPI(.pools),
                    responseType: [MayaPoolResponse].self
                )
                assetIds = response.data.filter { ($0.status ?? "").caseInsensitiveCompare("Available") == .orderedSame }.map { $0.asset }
            }
            return bucketize(assetIds: assetIds)
        } catch {
            logger.warning("native pool token fetch failed (\(proto.kind, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Resolve each pool-id to a curated `CoinMeta` and bucket by chain.
    /// Exposed for tests. `nonisolated` — touches no instance state.
    nonisolated static func bucketize(assetIds: [String]) -> [Chain: DestinationTokenBucket] {
        var byChain: [Chain: [CoinMeta]] = [:]
        var seen: [Chain: Set<String>] = [:]
        for assetId in assetIds {
            guard let coinMeta = NativePoolTokenMapper.coinMeta(forAssetId: assetId) else { continue }
            let chain = coinMeta.chain
            var chainSeen = seen[chain] ?? []
            guard !chainSeen.contains(coinMeta.uniqueId) else { continue }
            chainSeen.insert(coinMeta.uniqueId)
            seen[chain] = chainSeen
            byChain[chain, default: []].append(coinMeta)
        }
        var buckets: [Chain: DestinationTokenBucket] = [:]
        for (chain, tokens) in byChain {
            buckets[chain] = DestinationTokenBucket(
                chain: chain,
                tokens: tokens,
                uniqueIds: Set(tokens.map { $0.uniqueId })
            )
        }
        return buckets
    }
}

private extension NativeSwapProtocol {
    var kind: String {
        switch self {
        case .thorchain: return "thorchain"
        case .mayachain: return "mayachain"
        }
    }
}

/// Maps a native-protocol pool-id (`CHAIN.TICKER-0xCONTRACT`) to a curated
/// `CoinMeta`. The embedded contract disambiguates a same-ticker collision; it
/// is never a curated allowlist. Pools with no curated `TokensStore` match are
/// dropped (no logo / decimals to render).
enum NativePoolTokenMapper {

    /// Maps a pool-id chain prefix (`ETH`, `ARB`, …) to a `Chain`. Only EVM
    /// chains Vultisig has wallet support for are listed; others are dropped.
    static func chain(forPoolPrefix prefix: String) -> Chain? {
        switch prefix.uppercased() {
        case "ETH": return .ethereum
        case "ARB": return .arbitrum
        case "BSC": return .bscChain
        case "AVAX": return .avalanche
        case "BASE": return .base
        default: return nil
        }
    }

    static func coinMeta(forAssetId assetId: String) -> CoinMeta? {
        guard let dotIndex = assetId.firstIndex(of: ".") else { return nil }
        let prefix = String(assetId[..<dotIndex])
        let rest = String(assetId[assetId.index(after: dotIndex)...])
        guard !rest.isEmpty, let chain = chain(forPoolPrefix: prefix) else { return nil }

        let ticker: String
        let contract: String?
        if let dashIndex = rest.firstIndex(of: "-") {
            ticker = String(rest[..<dashIndex]).uppercased()
            let rawContract = String(rest[rest.index(after: dashIndex)...])
            contract = rawContract.isEmpty ? nil : rawContract.lowercased()
        } else {
            ticker = rest.uppercased()
            contract = nil
        }
        guard !ticker.isEmpty else { return nil }

        let curated = TokensStore.TokenSelectionAssets.filter { $0.chain == chain }
        // Prefer an exact contract match (disambiguates a same-ticker collision);
        // fall back to a ticker match for L1 natives and curated entries whose
        // contract casing differs.
        if let contract,
           let byContract = curated.first(where: { $0.contractAddress.lowercased() == contract }) {
            return byContract
        }
        return curated.first { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }
    }
}
