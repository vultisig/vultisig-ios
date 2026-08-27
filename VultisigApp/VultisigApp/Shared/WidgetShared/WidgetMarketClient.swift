//
//  WidgetMarketClient.swift
//  VultisigApp
//

import Foundation

enum WidgetMarketError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case emptyResponse
    case emptySelection
    case imageTooLarge
    case unapprovedImageURL
}

enum WidgetMarketAPI: TargetType {
    case marketData(query: WidgetMarketQuery, currency: String)
    case search(query: String)
    case icon(URL)

    private static let proxyBaseURL: URL = {
        guard let url = URL(string: "https://api.vultisig.com") else {
            preconditionFailure("Invalid Vultisig API base URL")
        }
        return url
    }()
    private static let approvedImageHost = "coin-images.coingecko.com"

    static func markets(query: WidgetMarketQuery, currency: String) throws -> Self {
        if case .ids = query, query.normalizedIDs.isEmpty {
            throw WidgetMarketError.emptySelection
        }
        return .marketData(query: query, currency: currency.lowercased())
    }

    static func validatedImageURL(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == approvedImageHost,
              url.user == nil,
              url.password == nil,
              url.port == nil else {
            throw WidgetMarketError.unapprovedImageURL
        }
        return url
    }

    static func validatedIcon(_ url: URL) throws -> Self {
        .icon(try validatedImageURL(url))
    }

    var baseURL: URL {
        switch self {
        case .marketData, .search:
            Self.proxyBaseURL
        case .icon(let url):
            url
        }
    }

    var path: String {
        switch self {
        case .marketData:
            "/coingeicko/api/v3/coins/markets"
        case .search:
            "/coingeicko/api/v3/search"
        case .icon:
            ""
        }
    }

    var method: HTTPMethod {
        .get
    }

    var task: HTTPTask {
        switch self {
        case .marketData(let query, let currency):
            var parameters: [String: Any] = [
                "vs_currency": currency,
                "order": "market_cap_desc",
                "per_page": query.limit,
                "page": 1,
                "sparkline": query.includesSparkline
            ]
            if query.includesSparkline {
                parameters["price_change_percentage"] = "24h"
            }
            if case .ids = query {
                parameters["ids"] = query.normalizedIDs.joined(separator: ",")
            }
            return .requestParameters(parameters, .urlEncoding)
        case .search(let query):
            return .requestParameters(["query": query], .urlEncoding)
        case .icon:
            return .requestPlain
        }
    }

    var timeoutInterval: TimeInterval {
        switch self {
        case .marketData:
            12
        case .search, .icon:
            8
        }
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

protocol WidgetMarketLookup: WidgetMarketRemote, WidgetAssetSearching {}

final class WidgetMarketClient: WidgetMarketLookup, @unchecked Sendable {
    private let httpClient: any HTTPClientProtocol
    private let decoder: JSONDecoder
    private let maximumIconByteCount: Int

    init(
        httpClient: any HTTPClientProtocol = HTTPClient(),
        decoder: JSONDecoder = JSONDecoder(),
        maximumIconByteCount: Int = 64 * 1_024
    ) {
        self.httpClient = httpClient
        self.decoder = decoder
        self.maximumIconByteCount = maximumIconByteCount
    }

    func markets(query: WidgetMarketQuery, currency: String) async throws -> [WidgetMarketAsset] {
        let target = try WidgetMarketAPI.markets(query: query, currency: currency)
        let response = try await httpClient.request(target)
        return try Self.decode(data: response.data, query: query, decoder: decoder)
    }

    func iconData(from url: URL) async throws -> Data {
        let response = try await httpClient.request(WidgetMarketAPI.validatedIcon(url))
        let data = response.data
        guard !data.isEmpty else { throw WidgetMarketError.emptyResponse }
        guard data.count <= maximumIconByteCount else { throw WidgetMarketError.imageTooLarge }
        return data
    }

    func searchAssets(matching query: String) async throws -> [WidgetAssetIdentity] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        let response = try await httpClient.request(WidgetMarketAPI.search(query: trimmedQuery))
        let responseBody = try decoder.decode(RemoteSearchResponse.self, from: response.data)
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
        case .top, .catalog:
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
            imageURL: image.flatMap { try? WidgetMarketAPI.validatedImageURL($0) },
            iconData: nil,
            currentPrice: currentPrice,
            priceChangePercentage24h: priceChangePercentage24h,
            marketCapRank: marketCapRank,
            sparkline: WidgetSparklineSampler.resample(finiteSparkline)
        )
    }
}
