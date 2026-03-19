//
//  SwapServiceFactory.swift
//  VultisigApp
//

import Foundation

enum SwapProviderType {
    case thorchain
    case mayachain
    case oneInch
    case kyberSwap
    case lifi
}

enum SwapServiceFactoryError: Error {
    case unsupportedSwapProvider(SwapProviderType)
}

class SwapServiceFactory {
    static func getService(forProvider provider: SwapProviderType) throws -> (any SwapServiceProtocol) {
        switch provider {
        case .thorchain:
            return ThorchainService.shared
        case .mayachain:
            return MayachainService.shared
        case .oneInch:
            return OneInchService.shared
        case .kyberSwap:
            return KyberSwapService.shared
        case .lifi:
            return LifiService.shared
        }
    }
}
