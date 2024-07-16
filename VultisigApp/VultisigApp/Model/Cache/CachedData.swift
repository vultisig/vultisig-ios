//
//  CachedData.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/07/24.
//

import Foundation

struct CachedData<T: Codable>: Codable {
    let data: T
    let timestamp: Date
}
