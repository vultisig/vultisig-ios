//
//  VultisigWidgetsBundle.swift
//  VultisigWidgets
//

import SwiftUI
import VultisigUIResources
import WidgetKit

@main
struct VultisigWidgetsBundle: WidgetBundle {
    init() {
        VultisigResources.registerFonts()
    }

    var body: some Widget {
        CryptoTickerWidget()
        TopCryptosWidget()
        CryptoWatchlistWidget()
    }
}
