//
//  CoinTypeExtension.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 19/03/2024.
//

import Foundation
import WalletCore

extension CoinType {
    static func from(string: String) -> CoinType? {
        let coinName = string.replacingOccurrences(of: "-", with: "")
        for coinType in CoinType.allCases where String(describing: coinType).lowercased() == coinName.lowercased() {
            return coinType
        }
        return nil
    }
    
    func getFixedDustThreshold() -> Int64 {
        switch self {
        case .bitcoin:
            return 546
        case .dogecoin:
            return 1000000
        case .litecoin,.dash,.zcash,.bitcoinCash:
            return 1000
        default:
            return 0
        }
    }
}
