//
//  SuiTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

struct SuiTransactionStatusResponse: Codable {
    let jsonrpc: String
    let id: Int
    let result: SuiTxResult?
    let error: SuiError?

    struct SuiTxResult: Codable {
        let effects: SuiEffects?
        let checkpoint: String?
    }

    struct SuiEffects: Codable {
        let status: SuiStatus
    }

    struct SuiStatus: Codable {
        let status: String  // "success" or "failure"
    }

    struct SuiError: Codable {
        let code: Int
        let message: String
    }
}
