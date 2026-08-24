//
//  WidgetMarketClient.swift
//  VultisigApp
//

import Foundation

// The WidgetKit extension cannot link the application's TargetType/HTTPClient
// graph. This small Foundation-only client is deliberately shared by the app
// and extension so the extension stays independently buildable.
// swiftlint:disable no_raw_urlsession no_raw_urlrequest

enum WidgetMarketError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case emptyResponse
    case emptySelection
    case imageTooLarge
}

enum WidgetMarketEndpoint {
    private static let baseURL = URL(string: "https://api.vultisig.com/coingeicko/api/v3/coins/markets")

    static func url(query: WidgetMarketQuery, currency: String) throws -> URL {
        guard let baseURL, var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WidgetMarketError.invalidURL
        }

        var items = [
            URLQueryItem(name: "vs_currency", value: currency.lowercased()),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: String(query.limit)),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "24h")
        ]

        if case .ids = query {
            guard !query.normalizedIDs.isEmpty else { throw WidgetMarketError.emptySelection }
            items.append(URLQueryItem(name: "ids", value: query.normalizedIDs.joined(separator: ",")))
        }

        components.queryItems = items
        guard let url = components.url else { throw WidgetMarketError.invalidURL }
        return url
    }
}

struct WidgetAssetIdentity: Equatable, Sendable, Identifiable {
    let id: String
    let symbol: String
    let name: String
}

protocol WidgetAssetSearching: Sendable {
    func searchAssets(matching query: String) async throws -> [WidgetAssetIdentity]
}

protocol WidgetMarketRemote: Sendable {
    func markets(query: WidgetMarketQuery, currency: String) async throws -> [WidgetMarketAsset]
    func iconData(from url: URL) async throws -> Data
}

final class WidgetMarketClient: WidgetMarketRemote, WidgetAssetSearching, @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let maximumIconByteCount: Int

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        maximumIconByteCount: Int = 128 * 1_024
    ) {
        self.session = session
        self.decoder = decoder
        self.maximumIconByteCount = maximumIconByteCount
    }

    func markets(query: WidgetMarketQuery, currency: String) async throws -> [WidgetMarketAsset] {
        let url = try WidgetMarketEndpoint.url(query: query, currency: currency)
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try Self.decode(data: data, query: query, decoder: decoder)
    }

    func iconData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        guard !data.isEmpty else { throw WidgetMarketError.emptyResponse }
        guard data.count <= maximumIconByteCount else { throw WidgetMarketError.imageTooLarge }
        return data
    }

    func searchAssets(matching query: String) async throws -> [WidgetAssetIdentity] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard let baseURL = URL(string: "https://api.vultisig.com/coingeicko/api/v3/search"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WidgetMarketError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "query", value: trimmedQuery)]
        guard let url = components.url else { throw WidgetMarketError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        let responseBody = try decoder.decode(RemoteSearchResponse.self, from: data)
        return responseBody.coins.prefix(20).map {
            WidgetAssetIdentity(id: $0.id.lowercased(), symbol: $0.symbol.uppercased(), name: $0.name)
        }
    }

    static func decode(
        data: Data,
        query: WidgetMarketQuery,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [WidgetMarketAsset] {
        let records = try decoder.decode([RemoteMarketAsset].self, from: data)
        let assets = records.compactMap(\.widgetAsset)
        guard !assets.isEmpty else { throw WidgetMarketError.emptyResponse }

        switch query {
        case .top:
            return Array(assets.prefix(query.limit))
        case .ids:
            let positions = Dictionary(
                uniqueKeysWithValues: query.normalizedIDs.enumerated().map { ($0.element, $0.offset) }
            )
            return assets.sorted {
                positions[$0.id, default: .max] < positions[$1.id, default: .max]
            }
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw WidgetMarketError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw WidgetMarketError.httpStatus(response.statusCode)
        }
    }
}

private struct RemoteSearchResponse: Decodable {
    let coins: [Coin]

    struct Coin: Decodable {
        let id: String
        let name: String
        let symbol: String
    }
}

private struct RemoteMarketAsset: Decodable {
    let id: String
    let symbol: String
    let name: String
    let image: URL?
    let currentPrice: Double?
    let priceChangePercentage24h: Double?
    let marketCapRank: Int?
    let sparklineIn7d: Sparkline?

    private enum CodingKeys: String, CodingKey {
        case id, symbol, name, image
        case currentPrice = "current_price"
        case priceChangePercentage24h = "price_change_percentage_24h"
        case marketCapRank = "market_cap_rank"
        case sparklineIn7d = "sparkline_in_7d"
    }

    struct Sparkline: Decodable {
        let price: [Double]
    }

    var widgetAsset: WidgetMarketAsset? {
        guard let currentPrice, currentPrice.isFinite else { return nil }
        let finiteSparkline = (sparklineIn7d?.price ?? []).filter(\.isFinite)
        return WidgetMarketAsset(
            id: id.lowercased(),
            symbol: symbol.uppercased(),
            name: name,
            imageURL: image,
            iconData: nil,
            currentPrice: currentPrice,
            priceChangePercentage24h: priceChangePercentage24h,
            marketCapRank: marketCapRank,
            sparkline: WidgetSparklineSampler.resample(finiteSparkline)
        )
    }
}

// swiftlint:enable no_raw_urlsession no_raw_urlrequest
