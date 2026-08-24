//
//  WatchlistConfigurationIntent.swift
//  VultisigWidgets
//

import AppIntents
import Foundation

struct WatchlistConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.cryptoWatchlist"
    static let description = IntentDescription("widget.cryptoWatchlist.choose")

    @Parameter(title: "widget.crypto1")
    var firstAsset: WidgetCryptoAssetEntity?

    @Parameter(title: "widget.crypto2")
    var secondAsset: WidgetCryptoAssetEntity?

    @Parameter(title: "widget.crypto3")
    var thirdAsset: WidgetCryptoAssetEntity?

    @Parameter(title: "widget.crypto4")
    var fourthAsset: WidgetCryptoAssetEntity?

    @Parameter(title: "widget.crypto5")
    var fifthAsset: WidgetCryptoAssetEntity?

    init() {}

    init(assets: [WidgetCryptoAssetEntity]) {
        firstAsset = assets[safe: 0]
        secondAsset = assets[safe: 1]
        thirdAsset = assets[safe: 2]
        fourthAsset = assets[safe: 3]
        fifthAsset = assets[safe: 4]
    }

    var selectedIDs: [String] {
        [firstAsset, secondAsset, thirdAsset, fourthAsset, fifthAsset]
            .compactMap { $0?.id }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
