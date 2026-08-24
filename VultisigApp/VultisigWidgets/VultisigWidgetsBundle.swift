//
//  VultisigWidgetsBundle.swift
//  VultisigWidgets
//

import SwiftUI
import WidgetKit

@main
struct VultisigWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CryptoTickerWidget()
        TopCryptosWidget()
    }
}
