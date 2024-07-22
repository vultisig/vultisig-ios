//
//  BlowfishResponse.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import Foundation

// Response structs
struct BlowfishResponse: Codable {
    let requestId: String
    let action: String
    let warnings: [BlowfishWarning]
    let simulationResults: BlowfishSimulationResults
    
    struct BlowfishWarning: Codable {
        let data: String
        let severity: String
        let kind: String
        let message: String
    }
    
    struct BlowfishSimulationResults: Codable {
        let aggregated: BlowfishAggregatedResults
        let perTransaction: [BlowfishPerTransaction]
        
        struct BlowfishAggregatedResults: Codable {
            let error: BlowfishSimulationError?
            let expectedStateChanges: [String: [BlowfishStateChange]]
            let userAccount: String
        }
        
        struct BlowfishSimulationError: Codable {
            let kind: String
            let humanReadableError: String
        }
        
        struct BlowfishStateChange: Codable {
            let value: String
        }
        
        struct BlowfishPerTransaction: Codable {
            let error: BlowfishTransactionError?
            let gas: BlowfishGas
            let protocolInfo: BlowfishProtocolInfo
            let logs: [BlowfishLog]
            let decodedLogs: [BlowfishDecodedLog]
            let decodedCalldata: BlowfishDecodedCalldata
            
            struct BlowfishTransactionError: Codable {
                let kind: String
                let humanReadableError: String
                let revertReason: String
            }
            
            struct BlowfishGas: Codable {
                let gasLimit: String
            }
            
            struct BlowfishProtocolInfo: Codable {
                let trustLevel: String
                let name: String
                let description: String
                let websiteUrl: String
                let imageUrl: String
            }
            
            struct BlowfishLog: Codable {
                let address: String
                let topics: [String]
                let data: String
            }
            
            struct BlowfishDecodedLog: Codable {
                let name: String
                let signature: String
                let params: [String]
            }
            
            struct BlowfishDecodedCalldata: Codable {
                let kind: String
                let data: String
            }
        }
    }
}

