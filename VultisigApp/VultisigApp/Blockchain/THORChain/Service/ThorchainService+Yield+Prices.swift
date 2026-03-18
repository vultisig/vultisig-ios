//
//  ThorchainService+Yield+Prices.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/09/25.
//

import Foundation

// MARK: - THORChain Yield Token Price
extension ThorchainService {

    func fetchYieldTokenPrice(for contract: String) async -> Double? {

        let urlString: String

        guard let yieldTokenTicker = TokensStore.TokenSelectionAssets.first(where: { $0.contractAddress == contract }).map({$0.ticker}) else {
            return nil
        }

        if yieldTokenTicker == "yRUNE" {
            urlString = Endpoint.fetchYRunePrice()
        } else if yieldTokenTicker == "yTCY" {
            urlString = Endpoint.fetchYtcyPrice()
        } else {
            return nil
        }

        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decodedResponse = try JSONDecoder().decode(YieldTokenPriceResponse.self, from: data)
            return Double(decodedResponse.data.navPerShare)
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
