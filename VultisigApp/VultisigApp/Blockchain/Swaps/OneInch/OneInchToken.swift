//
//  OneInchToken.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.05.2024.
//

import Foundation

struct OneInchToken: Codable, Hashable {
    let address: String
    let symbol: String
    let name: String
    let decimals: Int
    let logoURI: String?
    /// Source-of-truth list, present ONLY on 1inch's `/token/v1.2/{chain}/custom`
    /// response (bulk metadata by contract address). The EVM coin-finder requires
    /// `providers.contains("CoinGecko")` as a legitimacy signal — matches the
    /// SDK's `findEvmCoins` filter (see
    /// vultisig-sdk/packages/core/chain/coin/find/resolvers/evm/index.ts:69).
    ///
    /// The `/swap/v6.0/{chain}/tokens` whitelist does NOT return this field, so
    /// anything decoded off that endpoint always sees `nil` here — verified live
    /// across Ethereum / Arbitrum / Base / Polygon / BSC (5,005 tokens, zero with
    /// `providers`). Gate a `/tokens` consumer on `tags` instead.
    let providers: [String]?
    /// 1inch's per-token tag list, present on the `/swap/v6.0/{chain}/tokens`
    /// whitelist. Mixes descriptive tags (`stablecoin`, `defi`, `PEG:USD`) with a
    /// `RISK:*` family (`norisk`, `availability`, `unverified`, `suspicious`,
    /// `malicious`) — the only per-token trust signal that endpoint exposes.
    let tags: [String]?

    var logoUrl: URL? {
        return logoURI.flatMap { URL(string: $0) }
    }

    /// Legitimacy gate for the `/token/v1.2/{chain}/custom` path (the EVM
    /// coin-finder). Always `false` for tokens decoded from `/tokens`, which
    /// carries no `providers` field — see the property doc.
    var isCoinGeckoVerified: Bool {
        providers?.contains("CoinGecko") ?? false
    }
}

extension OneInchToken {
    func toCoinMeta(chain: Chain) -> CoinMeta {
        return CoinMeta(chain: chain,
                        ticker: self.symbol,
                        logo: self.logoURI ?? "",
                        decimals: self.decimals,
                        priceProviderId: .empty,
                        contractAddress: self.address,
                        isNativeToken: false)
    }

    /// Source label for tokens vouched for by 1inch's `/tokens` whitelist. The
    /// trust comes from 1inch curating the list, NOT from CoinGecko — that signal
    /// lives on a different endpoint and is never present here.
    static let catalogVerificationSource = "1inch"

    private static let riskTagPrefix = "RISK:"

    /// The only `RISK:*` values that do NOT hold a token back. `norisk` is
    /// 1inch's explicit all-clear; `availability` is a liquidity/routing property,
    /// not a legitimacy one. Everything else in the family — today
    /// `malicious` / `suspicious` / `unverified`, and anything 1inch adds later —
    /// downgrades, so a new classification fails closed rather than surfacing
    /// unreviewed.
    private static let benignRiskTags: Set<String> = [
        "RISK:norisk",
        "RISK:availability"
    ]

    /// Whether 1inch flags this token as risky on its own whitelist. Absence of
    /// any `RISK:` tag is not a flag — much of the whitelist is unannotated, and
    /// membership is itself the signal. Fail-closed on a conflict: a token
    /// carrying both `RISK:norisk` and `RISK:unverified` (1inch does emit that
    /// combination) is treated as risky.
    var isRiskFlaggedByOneInch: Bool {
        guard let tags else { return false }
        return tags.contains { tag in
            tag.hasPrefix(Self.riskTagPrefix) && !Self.benignRiskTags.contains(tag)
        }
    }

    /// Trust-carrying catalog candidate. `/swap/v6.0/{chain}/tokens` is 1inch's
    /// curated swap whitelist, so membership in it *is* the trust signal —
    /// `.verified(source: "1inch")`. Tokens 1inch itself tags risky are downgraded
    /// to `.unverified` so they stay badged and search-only rather than appearing
    /// in browse.
    ///
    /// Note: the whitelist carries no CoinGecko id, so `priceProviderId` stays
    /// empty; the curated bundled provider wins dedup and supplies it for known
    /// tokens.
    func toCatalogToken(chain: Chain, sourceKind: String) -> CatalogToken {
        let verification: TokenVerification = isRiskFlaggedByOneInch
            ? .unverified
            : .verified(source: Self.catalogVerificationSource)
        return CatalogToken(meta: toCoinMeta(chain: chain), verification: verification, sourceKind: sourceKind)
    }
}
