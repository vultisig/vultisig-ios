//
//  Coin+ChainAction+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//

#if os(iOS)
import SwiftUI

extension Array where Element == CoinAction {
    var filtered: [CoinAction] {
        let localeCode = Locale.current.region?.identifier
        if localeCode == "GB" || localeCode == "JP" || localeCode == "MY"{
            return filter { $0 != .swap }
        } else {
            return self
        }
    }
}
#endif
