//
//  WidgetSharedStorage.swift
//  VultisigApp
//
//  Constants shared by the application and WidgetKit extension. Keep this
//  file Foundation-only so both targets can compile it without importing the
//  application's service or model graphs.
//

import Foundation

enum WidgetSharedStorage {
    static let appGroupIdentifier = "group.com.vultisig.wallet"
    static let currencyKey = "marketWidgets.currency"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var currencyCode: String {
        defaults?.string(forKey: currencyKey) ?? "USD"
    }

    static func setCurrencyCode(_ value: String) {
        defaults?.set(value.uppercased(), forKey: currencyKey)
    }
}
