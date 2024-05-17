//
//  ThorchainSwapError.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 17.05.2024.
//

import Foundation

struct ThorchainSwapError: Codable, Error, LocalizedError {
    let error: String
    var errorDescription: String? { return error.capitalized }
}
