//
//  SwapProviderId.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/08/2025.
//

enum SwapProviderId: String, Codable {
    case oneInch = "1inch"
    case lifi = "li.fi"
    case kyberSwap = "kyber"

    var name: String {
        switch self {
        case .oneInch:
            return "1Inch"
        case .kyberSwap:
            return "KyberSwap"
        case .lifi:
            return "LI.FI"
        }
    }
}
