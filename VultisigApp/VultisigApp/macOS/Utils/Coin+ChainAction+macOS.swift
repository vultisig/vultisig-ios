//
//  Coin+ChainAction+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//

#if os(macOS)
import SwiftUI

extension Array where Element == CoinAction {
    var filtered: [CoinAction] {
        return self
    }
}
#endif
