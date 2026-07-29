//
//  BundledTokensProvider.swift
//  VultisigApp
//
//  The offline floor + trust anchor of the app-wide token catalog: wraps the
//  curated, hand-maintained static `TokensStore.TokenSelectionAssets` as a
//  `TokenCatalogProvider`. It is highest-precedence (its curated logo /
//  priceProviderId win any dedup collision against a dynamic source), always
//  `.curated`, and does no network — so the catalog is never empty offline and
//  everything else (1inch / Jupiter / …) is purely additive on top.
//
//  Honors the same chain-visibility gates as the coin-selection list
//  (`CoinSelectionViewModel.groupAssets`): the `sepolia` / `thorchainChainnet`
//  UserDefaults flags and the QBTC (MLDSA) feature flag. The vault-specific
//  MLDSA-key-presence gate is NOT applied here — this provider is
//  vault-independent; that check stays in the view model where the vault is in
//  scope.
//

import Foundation

@MainActor
final class BundledTokensProvider: TokenCatalogProvider {
    static let shared = BundledTokensProvider()

    let kind = "bundled"
    /// Highest precedence: the curated bundle wins every `uniqueId` collision so
    /// its logo + priceProviderId survive against dynamic sources.
    let precedence = Int.max
    let verification: TokenVerification = .curated

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Bundled is a synchronous, in-memory source; async only to satisfy the
    // protocol (dynamic providers await network).
    // swiftlint:disable:next async_without_await
    func tokens(for chain: Chain, forceRefresh _: Bool) async -> DestinationTokenBucket {
        let metas = Self.curatedTokens(for: chain, defaults: defaults)
        return DestinationTokenBucket(chain: chain, tokens: metas, uniqueIds: Set(metas.map(\.uniqueId)))
    }

    /// Curated `TokensStore` tokens for `chain`, gated by chain visibility.
    /// `nonisolated` static + injectable `defaults` so tests drive the gates
    /// without touching `.standard`.
    nonisolated static func curatedTokens(for chain: Chain, defaults: UserDefaults) -> [CoinMeta] {
        guard isChainVisible(chain, defaults: defaults) else { return [] }
        // Sepolia's native token isn't in `TokenSelectionAssets`; the
        // coin-selection list injects it explicitly, so mirror that here for parity.
        if chain == .ethereumSepolia {
            return [TokensStore.Token.ethSepolia]
        }
        return TokensStore.TokenSelectionAssets.filter { $0.chain == chain }
    }

    /// Chain-visibility gates mirroring `CoinSelectionViewModel.groupAssets`
    /// (the vault-independent subset). Sepolia isn't present in
    /// `TokenSelectionAssets`, so its gate is effectively moot for this provider
    /// but kept for parity / intent.
    nonisolated static func isChainVisible(_ chain: Chain, defaults: UserDefaults) -> Bool {
        switch chain {
        case .ethereumSepolia:
            return defaults.bool(forKey: "sepolia")
        case .thorChainChainnet, .thorChainStagenet:
            return defaults.bool(forKey: "thorchainChainnet")
        default:
            if chain.signingKeyType == .MLDSA {
                return QBTCConfig.isFeatureEnabled
            }
            return true
        }
    }
}
