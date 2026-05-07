//
//  CardanoNativeTokensService.swift
//  VultisigApp
//

import Foundation
import OSLog

actor CardanoNativeTokensService {

    static let shared = CardanoNativeTokensService()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "cardano-native-tokens")
    private let httpClient: HTTPClientProtocol
    private var assetInfoCache: [String: CachedMetadata] = [:]
    private let cacheTTL: TimeInterval = 7 * 24 * 60 * 60

    private struct CachedMetadata {
        let metadata: CardanoTokenMetadata
        let storedAt: Date
    }

    private init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Discover all native tokens held at the given Cardano address. Mirrors
    /// `findCardanoCoins` in vultisig-sdk: hits `address_assets` and derives a
    /// short ticker from the hex-decoded asset_name with a policy-id prefix
    /// fallback. Registry-rich metadata (logo, registry name) requires a
    /// follow-up `resolveMetadata` call.
    func discoverTokens(address: String) async throws -> [CardanoTokenMetadata] {
        let response = try await httpClient.request(
            CardanoAPI.addressAssets(addresses: [address]),
            responseType: [CardanoAssetEntry].self
        )

        return response.data.map(Self.makeMetadata(from:))
    }

    static func makeMetadata(from asset: CardanoAssetEntry) -> CardanoTokenMetadata {
        let policyId = asset.policyId.lowercased()
        let assetNameHex = (asset.assetName ?? "").lowercased()
        let assetId = CardanoAssetId.make(policyId: policyId, assetName: assetNameHex)
        let ticker = hexToAscii(assetNameHex).nonEmptyOrNil
            ?? String(policyId.prefix(8)).uppercased()
        return CardanoTokenMetadata(
            assetId: assetId,
            policyId: policyId,
            assetNameHex: assetNameHex,
            fingerprint: asset.fingerprint,
            ticker: ticker,
            decimals: asset.decimals ?? 0,
            registryName: nil,
            registryUrl: nil,
            registryLogo: nil
        )
    }

    /// Resolve token metadata from `asset_info` (used by the custom-token-add
    /// flow). Cached per assetId for `cacheTTL` to keep Koios load reasonable
    /// across repeated balance refreshes.
    func resolveMetadata(assetId: String) async throws -> CardanoTokenMetadata {
        if let cached = assetInfoCache[assetId], Date().timeIntervalSince(cached.storedAt) < cacheTTL {
            return cached.metadata
        }

        let parsed = try CardanoAssetId.parse(assetId)
        let response = try await httpClient.request(
            CardanoAPI.assetInfo(assets: [(policyId: parsed.policyId, assetNameHex: parsed.assetName)]),
            responseType: [CardanoAssetInfoEntry].self
        )

        guard let info = response.data.first else {
            throw CardanoNativeTokensServiceError.assetNotFound(assetId)
        }

        let registry = info.tokenRegistryMetadata
        let ticker = registry?.ticker?.trimmedNonEmpty
            ?? info.assetNameAscii?.trimmedNonEmpty
            ?? String(parsed.assetName.prefix(8)).uppercased()
        let decimals = registry?.decimals ?? info.decimals ?? 0

        let metadata = CardanoTokenMetadata(
            assetId: assetId,
            policyId: parsed.policyId,
            assetNameHex: parsed.assetName,
            fingerprint: info.fingerprint,
            ticker: ticker,
            decimals: decimals,
            registryName: registry?.ticker,
            registryUrl: registry?.url,
            registryLogo: registry?.logo
        )

        assetInfoCache[assetId] = CachedMetadata(metadata: metadata, storedAt: Date())
        return metadata
    }

    func clearCache() {
        assetInfoCache.removeAll()
    }
}

enum CardanoNativeTokensServiceError: Error, Equatable {
    case assetNotFound(String)
}

func hexToAscii(_ hex: String) -> String {
    var bytes: [UInt8] = []
    var iterator = hex.makeIterator()
    while let high = iterator.next(), let low = iterator.next() {
        guard
            let highValue = high.hexDigitValue,
            let lowValue = low.hexDigitValue
        else { return "" }
        bytes.append(UInt8(highValue * 16 + lowValue) & 0x7F)
    }
    return String(bytes: bytes, encoding: .ascii) ?? ""
}

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
