//
//  CoinMarketStats.swift
//  VultisigApp
//
//  Market snapshot for one coin, decoded from the CoinGecko proxy's
//  `/coins/markets` record.
//

import Foundation

/// Market cap, supply and all-time extremes for a single coin, in the currency
/// the request asked for.
///
/// Every numeric field is optional: CoinGecko returns `null` for anything it
/// cannot compute (no fully-diluted valuation without a total supply, no
/// `max_supply` for an uncapped asset), and a token whose record is half-filled
/// should still show the rows it does have.
struct CoinMarketStats: Equatable, Sendable {
    let id: String
    let currentPrice: Double?
    let marketCap: Double?
    let marketCapRank: Int?
    let fullyDilutedValuation: Double?
    let totalVolume: Double?
    let high24h: Double?
    let low24h: Double?
    let priceChangePercentage24h: Double?
    let circulatingSupply: Double?
    let totalSupply: Double?
    let maxSupply: Double?
    let ath: Double?
    let athChangePercentage: Double?
    let athDate: Date?
    let atl: Double?
    let atlChangePercentage: Double?
    let atlDate: Date?

    /// Whether the 24h low/high band can be drawn — it needs both ends and a
    /// current price to place the marker, and a non-degenerate span.
    var has24hRange: Bool {
        guard let low = low24h, let high = high24h, high > low, currentPrice != nil else {
            return false
        }
        return true
    }

    /// Where the current price sits inside the 24h band, `0` at the low and `1`
    /// at the high. `nil` when the band is unusable.
    var positionIn24hRange: Double? {
        guard let low = low24h, let high = high24h, let price = currentPrice, high > low else {
            return nil
        }
        return min(1, max(0, (price - low) / (high - low)))
    }
}

// MARK: - Decoding

extension CoinMarketStats: Decodable {

    private enum CodingKeys: String, CodingKey {
        case id
        case currentPrice = "current_price"
        case marketCap = "market_cap"
        case marketCapRank = "market_cap_rank"
        case fullyDilutedValuation = "fully_diluted_valuation"
        case totalVolume = "total_volume"
        case high24h = "high_24h"
        case low24h = "low_24h"
        case priceChangePercentage24h = "price_change_percentage_24h"
        case circulatingSupply = "circulating_supply"
        case totalSupply = "total_supply"
        case maxSupply = "max_supply"
        case ath
        case athChangePercentage = "ath_change_percentage"
        case athDate = "ath_date"
        case atl
        case atlChangePercentage = "atl_change_percentage"
        case atlDate = "atl_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.currentPrice = try container.decodeIfPresent(Double.self, forKey: .currentPrice)
        self.marketCap = try container.decodeIfPresent(Double.self, forKey: .marketCap)
        self.marketCapRank = try container.decodeIfPresent(Int.self, forKey: .marketCapRank)
        self.fullyDilutedValuation = try container.decodeIfPresent(Double.self, forKey: .fullyDilutedValuation)
        self.totalVolume = try container.decodeIfPresent(Double.self, forKey: .totalVolume)
        self.high24h = try container.decodeIfPresent(Double.self, forKey: .high24h)
        self.low24h = try container.decodeIfPresent(Double.self, forKey: .low24h)
        self.priceChangePercentage24h = try container.decodeIfPresent(Double.self, forKey: .priceChangePercentage24h)
        self.circulatingSupply = try container.decodeIfPresent(Double.self, forKey: .circulatingSupply)
        self.totalSupply = try container.decodeIfPresent(Double.self, forKey: .totalSupply)
        self.maxSupply = try container.decodeIfPresent(Double.self, forKey: .maxSupply)
        self.ath = try container.decodeIfPresent(Double.self, forKey: .ath)
        self.athChangePercentage = try container.decodeIfPresent(Double.self, forKey: .athChangePercentage)
        self.atl = try container.decodeIfPresent(Double.self, forKey: .atl)
        self.atlChangePercentage = try container.decodeIfPresent(Double.self, forKey: .atlChangePercentage)

        // The dates arrive as ISO-8601 with fractional seconds
        // ("2025-10-06T18:57:42.558Z"). The shared `HTTPClient` decodes with a
        // stock `JSONDecoder`, whose `.iso8601` strategy rejects the fractional
        // part, so these are parsed here instead of via a decoder strategy.
        self.athDate = Self.parseTimestamp(try container.decodeIfPresent(String.self, forKey: .athDate))
        self.atlDate = Self.parseTimestamp(try container.decodeIfPresent(String.self, forKey: .atlDate))
    }

    static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}
