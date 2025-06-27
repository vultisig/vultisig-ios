//
//  CosmosServiceFactory.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025/01/08.
//

import Foundation

class CosmosServiceFactory {
    
    static func getService(forChain chain: Chain) throws -> CosmosService {
        switch chain {
        case .gaiaChain:
            return GaiaService.shared
        case .dydx:
            return DydxService.shared
        case .kujira:
            return KujiraService.shared
        case .osmosis:
            return OsmosisService.shared
        case .terra:
            return TerraService.shared
        case .terraClassic:
            return TerraClassicService.shared
        case .noble:
            return NobleService.shared
        case .akash:
            return AkashService.shared
        default:
            throw CosmosServiceError.unsupportedChain
        }
    }
}

enum CosmosServiceError: Error, LocalizedError {
    case unsupportedChain
    
    var errorDescription: String? {
        switch self {
        case .unsupportedChain:
            return "Unsupported Cosmos chain"
        }
    }
} 