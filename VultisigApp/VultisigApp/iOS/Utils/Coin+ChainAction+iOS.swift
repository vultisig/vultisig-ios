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
//#if DEBUG
        return self
/*#else
        let allowSwap = UserDefaults.standard.bool(forKey: "allowSwap")
        if allowSwap {
            return self
        }
        return filter { $0 != .swap }
#endif*/
    }
}
#endif
