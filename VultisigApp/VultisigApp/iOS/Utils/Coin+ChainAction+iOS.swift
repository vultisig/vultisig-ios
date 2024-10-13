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
#if DEBUG
        return self
#else
        return filter { $0 != .swap }
#endif
    }
}
#endif
