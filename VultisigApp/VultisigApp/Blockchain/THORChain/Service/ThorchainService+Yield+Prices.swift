//
//  ThorchainService+Yield+Prices.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/09/25.
//

import Foundation

/// TargetType for THORChain yield-token price CosmWasm smart-queries.
/// Each contract exposes the same `{"status":{}}` query, base64-encoded
/// as a path segment — we pin those segments per-case rather than
/// computing them so the URL stays stable across builds.
enum ThorchainYieldPriceAPI: TargetType {
    case yRunePrice
    case ytcyPrice
    case ybRunePrice

    var baseURL: URL { URL(string: "https://thorchain.ibs.team")! }

    var path: String {
        switch self {
        case .yRunePrice:
            return "/api/cosmwasm/wasm/v1/contract/thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt/smart/eyJzdGF0dXMiOiB7fX0="
        case .ytcyPrice:
            return "/api/cosmwasm/wasm/v1/contract/thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px/smart/eyJzdGF0dXMiOiB7fX0="
        case .ybRunePrice:
            // Same `{"status":{}}` smart query, pinned against the bRUNE liquid-bond contract.
            return "/api/cosmwasm/wasm/v1/contract/\(BRUNEStakingConstants.contract)/smart/eyJzdGF0dXMiOiB7fX0="
        }
    }

    var method: HTTPMethod { .get }
    var task: HTTPTask { .requestPlain }
}

// MARK: - THORChain Yield Token Price
extension ThorchainService {

    func fetchYieldTokenPrice(for contract: String) async -> Double? {
        guard let yieldTokenTicker = TokensStore.TokenSelectionAssets.first(where: { $0.contractAddress == contract }).map({ $0.ticker }) else {
            return nil
        }

        // ybRUNE's `{"status":{}}` reports a bond ratio, not `nav_per_share`, and
        // needs the RUNE rate to reach USD — handled on its own path below.
        if yieldTokenTicker == "ybRUNE" {
            return await fetchYbRunePrice()
        }

        let target: ThorchainYieldPriceAPI
        if yieldTokenTicker == "yRUNE" {
            target = .yRunePrice
        } else if yieldTokenTicker == "yTCY" {
            target = .ytcyPrice
        } else {
            return nil
        }

        do {
            let response = try await httpClient.request(target, responseType: YieldTokenPriceResponse.self)
            return Double(response.data.data.navPerShare)
        } catch {
            logger.debug("Failed to fetch yield token price for \(contract): \(error.localizedDescription)")
            return nil
        }
    }

    /// USD price for ybRUNE. Its `{"status":{}}` reports the bond
    /// `liquid_bond_size / liquid_bond_shares` ratio (bRUNE per ybRUNE) rather
    /// than a `nav_per_share`, so USD = ratio × bRUNE. bRUNE trades at ~RUNE
    /// parity, so we scale by the already-fetched RUNE rate — `CryptoPriceService`
    /// resolves provider-id prices (RUNE) before contract prices (ybRUNE), so the
    /// rate is present by the time this runs.
    private func fetchYbRunePrice() async -> Double? {
        do {
            let response = try await httpClient.request(
                ThorchainYieldPriceAPI.ybRunePrice,
                responseType: BRuneStatusResponse.self
            )
            guard let ratio = Self.navRatio(
                size: response.data.data.liquidBondSize,
                shares: response.data.data.liquidBondShares
            ) else {
                return nil
            }
            // USD specifically: the ybRUNE rate is persisted as fiat "usd" (like
            // yRUNE/yTCY), so the NAV ratio must scale the RUNE *USD* rate, not the
            // user's display-currency rate.
            guard let runeRate = RateProvider.shared.rate(for: TokensStore.rune, currency: .USD) else {
                logger.debug("ybRUNE price unavailable: RUNE USD rate not yet fetched")
                return nil
            }
            return ratio * runeRate.value
        } catch {
            logger.debug("Failed to fetch ybRUNE price: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pure NAV computation for the bRUNE liquid-bond contract: bRUNE per ybRUNE
    /// (`liquid_bond_size / liquid_bond_shares`). Returns `nil` for unparseable
    /// input or non-positive share supply.
    static func navRatio(size: String, shares: String) -> Double? {
        guard let sizeVal = Decimal(string: size),
              let sharesVal = Decimal(string: shares),
              sharesVal > 0 else {
            return nil
        }
        return NSDecimalNumber(decimal: sizeVal / sharesVal).doubleValue
    }

    public struct YieldTokenPriceResponse: Codable {
        public let data: YieldTokenPriceData
    }

    public struct YieldTokenPriceData: Codable {
        let navPerShare: String

        enum CodingKeys: String, CodingKey {
            case navPerShare = "nav_per_share"
        }
    }

    /// `{"status":{}}` response for the bRUNE liquid-bond contract. Only the two
    /// NAV fields are decoded; the contract also returns bond/revenue fields we
    /// don't need for pricing.
    struct BRuneStatusResponse: Codable {
        let data: BRuneStatusData
    }

    struct BRuneStatusData: Codable {
        let liquidBondSize: String
        let liquidBondShares: String

        enum CodingKeys: String, CodingKey {
            case liquidBondSize = "liquid_bond_size"
            case liquidBondShares = "liquid_bond_shares"
        }
    }
}
