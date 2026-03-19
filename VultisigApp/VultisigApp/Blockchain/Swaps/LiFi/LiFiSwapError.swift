//
//  LiFiSwapError.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.01.2025.
//

import Foundation

struct LiFiSwapError: Codable, Error, LocalizedError {
    let message: String
    var errorDescription: String? { return message.capitalized }
}
