//
//  BlowfishRequest.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import Foundation

// Request structs
struct BlowfishRequest: Codable {
    let userAccount: String
    let metadata: BlowfishMetadata
    let txObjects: [BlowfishTxObject]
    let simulatorConfig: BlowfishSimulatorConfig?
    
    struct BlowfishTxObject: Codable {
        let from: String
        let to: String
        let value: String
        let data: String?
    }
    
    struct BlowfishMetadata: Codable {
        let origin: String
    }
    
    struct BlowfishSimulatorConfig: Codable {
        let blockNumber: String?
        let stateOverrides: BlowfishStateOverrides?
    }
    
    struct BlowfishStateOverrides: Codable {
        let nativeBalances: [BlowfishNativeBalance]?
        let storage: [BlowfishStorage]?
    }
    
    struct BlowfishNativeBalance: Codable {
        let address: String
        let value: String
    }
    
    struct BlowfishStorage: Codable {
        let address: String
        let slot: String
        let value: String
    }
}
