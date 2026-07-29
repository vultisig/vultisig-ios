//
//  CoinMarketStatsTests.swift
//  VultisigAppTests
//
//  Decoding of the `/coins/markets` record — including the fractional-second
//  ATH/ATL timestamps a stock `.iso8601` strategy rejects, and the nulls
//  CoinGecko returns for uncapped or un-valued assets.
//

@testable import VultisigApp
import Foundation
import XCTest

final class CoinMarketStatsTests: XCTestCase {

    /// Trimmed copy of the live `/coins/markets?ids=bitcoin` record.
    private static let fullPayload = Data(#"""
    {
      "id": "bitcoin",
      "symbol": "btc",
      "name": "Bitcoin",
      "current_price": 63916,
      "market_cap": 1282270987961,
      "market_cap_rank": 1,
      "fully_diluted_valuation": 1282270987961,
      "total_volume": 24154575770,
      "high_24h": 64008,
      "low_24h": 62828,
      "price_change_24h": 314.13,
      "price_change_percentage_24h": 0.4939,
      "circulating_supply": 20062562.0,
      "total_supply": 20062562.0,
      "max_supply": 21000000.0,
      "ath": 126080,
      "ath_change_percentage": -49.30513,
      "ath_date": "2025-10-06T18:57:42.558Z",
      "atl": 67.81,
      "atl_change_percentage": 94158.93421,
      "atl_date": "2013-07-06T00:00:00.000Z",
      "roi": null
    }
    """#.utf8)

    func testDecodesTheFullRecord() throws {
        let stats = try JSONDecoder().decode(CoinMarketStats.self, from: Self.fullPayload)

        XCTAssertEqual(stats.id, "bitcoin")
        XCTAssertEqual(stats.currentPrice, 63916)
        XCTAssertEqual(stats.marketCap, 1_282_270_987_961)
        XCTAssertEqual(stats.marketCapRank, 1)
        XCTAssertEqual(stats.totalVolume, 24_154_575_770)
        XCTAssertEqual(stats.maxSupply, 21_000_000)
        XCTAssertEqual(stats.ath, 126_080)
        XCTAssertEqual(stats.atl, 67.81)
    }

    func testDecodesFractionalSecondTimestamps() throws {
        let stats = try JSONDecoder().decode(CoinMarketStats.self, from: Self.fullPayload)

        let athDate = try XCTUnwrap(stats.athDate)
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC") ?? .gmt,
            from: athDate
        )
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 6)
        XCTAssertNotNil(stats.atlDate)
    }

    func testDecodesTimestampsWithoutFractionalSeconds() {
        // Not what the proxy returns today, but the fallback parser exists so a
        // format change doesn't blank the ATH row.
        XCTAssertNotNil(CoinMarketStats.parseTimestamp("2025-10-06T18:57:42Z"))
    }

    func testUnparseableTimestampBecomesNil() {
        XCTAssertNil(CoinMarketStats.parseTimestamp("not a date"))
        XCTAssertNil(CoinMarketStats.parseTimestamp(nil))
    }

    func testDecodesRecordWithNullsForUncappedAsset() throws {
        let json = Data(#"""
        {
          "id": "ethereum",
          "current_price": 3000,
          "market_cap": 360000000000,
          "market_cap_rank": 2,
          "fully_diluted_valuation": null,
          "total_volume": 12000000000,
          "high_24h": null,
          "low_24h": null,
          "circulating_supply": 120000000,
          "total_supply": null,
          "max_supply": null,
          "ath": 4878,
          "ath_change_percentage": -38.5,
          "ath_date": "2021-11-10T14:24:19.604Z",
          "atl": 0.432979,
          "atl_change_percentage": 692000.0,
          "atl_date": "2015-10-20T00:00:00.000Z"
        }
        """#.utf8)

        let stats = try JSONDecoder().decode(CoinMarketStats.self, from: json)

        XCTAssertNil(stats.maxSupply)
        XCTAssertNil(stats.fullyDilutedValuation)
        XCTAssertNil(stats.totalSupply)
        XCTAssertFalse(stats.has24hRange)
        XCTAssertNil(stats.positionIn24hRange)
        XCTAssertEqual(stats.marketCapRank, 2)
    }

    func testDecodesMinimalRecordWithOnlyAnId() throws {
        let stats = try JSONDecoder().decode(CoinMarketStats.self, from: Data(#"{"id":"vult"}"#.utf8))

        XCTAssertEqual(stats.id, "vult")
        XCTAssertNil(stats.marketCap)
        XCTAssertNil(stats.athDate)
    }

    func testDecodeThrowsWithoutAnId() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(CoinMarketStats.self, from: Data(#"{"market_cap":1}"#.utf8))
        )
    }

    // MARK: - 24h band

    func testPositionInRangeIsAFractionOfTheBand() throws {
        let stats = try JSONDecoder().decode(CoinMarketStats.self, from: Self.fullPayload)

        XCTAssertTrue(stats.has24hRange)
        let position = try XCTUnwrap(stats.positionIn24hRange)
        XCTAssertGreaterThan(position, 0)
        XCTAssertLessThan(position, 1)
    }

    func testPositionInRangeClampsAPriceOutsideTheBand() throws {
        // The `/markets` snapshot can be a few seconds staler than the spot
        // price, putting `current_price` marginally outside `low_24h...high_24h`.
        let json = Data(#"{"id":"x","current_price":200,"low_24h":10,"high_24h":100}"#.utf8)
        let stats = try JSONDecoder().decode(CoinMarketStats.self, from: json)

        XCTAssertEqual(try XCTUnwrap(stats.positionIn24hRange), 1)
    }

    func testDegenerateBandIsRejected() throws {
        let json = Data(#"{"id":"x","current_price":50,"low_24h":50,"high_24h":50}"#.utf8)
        let stats = try JSONDecoder().decode(CoinMarketStats.self, from: json)

        XCTAssertFalse(stats.has24hRange)
        XCTAssertNil(stats.positionIn24hRange)
    }
}
