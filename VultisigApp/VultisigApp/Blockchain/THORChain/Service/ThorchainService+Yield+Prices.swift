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

    var baseURL: URL { URL(string: "https://thorchain.ibs.team")! }

    var path: String {
        switch self {
        case .yRunePrice:
            return "/api/cosmwasm/wasm/v1/contract/thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt/smart/eyJzdGF0dXMiOiB7fX0="
        case .ytcyPrice:
            return "/api/cosmwasm/wasm/v1/contract/thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px/smart/eyJzdGF0dXMiOiB7fX0="
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

    public struct YieldTokenPriceResponse: Codable {
        public let data: YieldTokenPriceData
    }

    public struct YieldTokenPriceData: Codable {
        let navPerShare: String

        enum CodingKeys: String, CodingKey {
            case navPerShare = "nav_per_share"
        }
    }
}
