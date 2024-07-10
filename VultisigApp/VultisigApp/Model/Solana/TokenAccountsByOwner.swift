//
//  SolanaRpcTokenOwner.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/07/24.
//

import Foundation

extension SolanaService {
    class SolanaTokenAccount: Decodable {
        let account: SolanaAccountData
        let pubkey: String
    }
    
    class SolanaAccountData: Decodable {
        let data: SolanaParsedData
        let executable: Bool
        let lamports: Int
        let owner: String
        let rentEpoch: UInt64
        let space: Int
    }
    
    class SolanaParsedData: Decodable {
        let parsed: SolanaParsedInfo
        let program: String
        let space: Int
    }
    
    class SolanaParsedInfo: Decodable {
        let info: SolanaAccountInfo
        let type: String
    }
    
    class SolanaAccountInfo: Decodable {
        let isNative: Bool
        let mint: String
        let owner: String
        let state: String
        let tokenAmount: SolanaTokenAmount
    }
    
    class SolanaTokenAmount: Decodable {
        let amount: String
        let decimals: Int
        let uiAmount: Double
        let uiAmountString: String
    }
    
    func parseSolanaTokenResponse(jsonData: Data) throws -> SolanaService.SolanaDetailedRPCResult<[SolanaService.SolanaTokenAccount]> {
        return try JSONDecoder().decode(SolanaService.SolanaDetailedRPCResult<[SolanaService.SolanaTokenAccount]>.self, from: jsonData)
    }
            
}







