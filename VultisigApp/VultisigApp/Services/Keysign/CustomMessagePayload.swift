//
//  CustomMessagePayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.11.2024.
//

import Foundation

struct CustomMessagePayload: Codable, Hashable {
    let method: String
    let message: String
}
