//
//  BlowfishSolanaRequest.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/07/24.
//

import Foundation

// Request structs
struct BlowfishSolanaRequest: Codable {
    
    let userAccount: String
    let metadata: BlowfishMetadata
    let transactions: [String]
        
    struct BlowfishMetadata: Codable {
        let origin: String
    }
    
}

struct BlowfishSolanaRequestError: Codable {
    
    let error: String
    let requestId: String
    
}
