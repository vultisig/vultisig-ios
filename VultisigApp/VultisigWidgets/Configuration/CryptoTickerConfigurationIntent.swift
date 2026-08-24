//
//  CryptoTickerConfigurationIntent.swift
//  VultisigWidgets
//

import AppIntents
import Foundation

struct WidgetCryptoAssetEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.cryptocurrency")
    static let defaultQuery = WidgetCryptoAssetEntityQuery()

    let id: String
    let symbol: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(symbol)", subtitle: "\(name)")
    }

    init(id: String, symbol: String, name: String) {
        self.id = id
        self.symbol = symbol
        self.name = name
    }

    init(_ identity: WidgetAssetIdentity) {
        self.init(id: identity.id, symbol: identity.symbol, name: identity.name)
    }

    init(_ asset: WidgetMarketAsset) {
        self.init(id: asset.id, symbol: asset.symbol, name: asset.name)
    }

    static let bitcoin = WidgetCryptoAssetEntity(id: "bitcoin", symbol: "BTC", name: "Bitcoin")
}

struct WidgetCryptoAssetEntityQuery: EntityStringQuery {
    private let client = WidgetMarketClient()

    func entities(for identifiers: [String]) async throws -> [WidgetCryptoAssetEntity] {
        guard !identifiers.isEmpty else { return [] }
        return try await client
            .markets(query: .ids(identifiers), currency: "usd")
            .map(WidgetCryptoAssetEntity.init)
    }

    func entities(matching string: String) async throws -> [WidgetCryptoAssetEntity] {
        try await client
            .searchAssets(matching: string)
            .map(WidgetCryptoAssetEntity.init)
    }

    // EntityQuery requires async even though the curated suggestions are local.
    // swiftlint:disable:next async_without_await
    func suggestedEntities() async throws -> [WidgetCryptoAssetEntity] {
        Self.suggestions
    }

    private static let suggestions = [
        WidgetCryptoAssetEntity.bitcoin,
        WidgetCryptoAssetEntity(id: "ethereum", symbol: "ETH", name: "Ethereum"),
        WidgetCryptoAssetEntity(id: "tether", symbol: "USDT", name: "Tether"),
        WidgetCryptoAssetEntity(id: "binancecoin", symbol: "BNB", name: "BNB"),
        WidgetCryptoAssetEntity(id: "solana", symbol: "SOL", name: "Solana"),
        WidgetCryptoAssetEntity(id: "usd-coin", symbol: "USDC", name: "USDC"),
        WidgetCryptoAssetEntity(id: "ripple", symbol: "XRP", name: "XRP"),
        WidgetCryptoAssetEntity(id: "dogecoin", symbol: "DOGE", name: "Dogecoin")
    ]
}

struct CryptoTickerConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.cryptoTicker"
    static let description = IntentDescription("widget.cryptoTicker.choose")

    @Parameter(title: "widget.cryptocurrency")
    var asset: WidgetCryptoAssetEntity?

    init() {}

    init(asset: WidgetCryptoAssetEntity) {
        self.asset = asset
    }
}
