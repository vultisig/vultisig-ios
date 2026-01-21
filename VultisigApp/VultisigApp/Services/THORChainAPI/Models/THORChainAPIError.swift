//
//  THORChainAPIError.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/08/2025.
//

import Foundation

enum THORChainAPIError: Error, LocalizedError {
    case invalidResponse
    case thornameNotFound
    case addressNotFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from THORChain API"
        case .thornameNotFound:
            return "THORName doesn't exist"
        case .addressNotFound:
            return "Address doesn't have a thorname"
        }
    }
}

struct THORChainErrorResponse: Codable {
    let code: Int
    let message: String
    let details: [String]
}
