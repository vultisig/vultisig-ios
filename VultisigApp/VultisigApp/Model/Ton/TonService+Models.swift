//
//  TonService+Models.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 29/08/25.
//

struct JettonWalletsResponse: Codable {
    let jetton_wallets: [JettonWalletInfo]
}

struct JettonWalletInfo: Codable {
    let address: String
    let balance: String
    let owner: String  // Raw address string, not a dictionary
    let jetton: String // Raw address string, not a dictionary
    let last_transaction_lt: String?
    let code_hash: String?
    let data_hash: String?
}

struct RunGetMethodResponse: Codable {
    let ok: Bool
    let result: RunGetMethodResult?
    let error: String?
}

struct RunGetMethodResult: Codable {
    let stack: [StackItem]?
    let gas_used: Int64?
    let exit_code: Int?
}

struct StackItem: Codable {
    let type: String?
    let value: StackValue?
    let boc: String?
    
    private enum CodingKeys: String, CodingKey {
        case type, value, boc
    }
}

struct StackValue: Codable {
    let bytes: String?
    let b64: String?
    let boc: String?
    
    private enum CodingKeys: String, CodingKey {
        case bytes, b64, boc
    }
}

struct ApiResponse<T: Codable>: Codable {
    let ok: Bool
    let result: T?
    let error: String?
    let code: Int?
}

struct TonBroadcastSuccessResponse: Codable {
    let hash: String
}
