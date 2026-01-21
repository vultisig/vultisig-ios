//
//  SolanaRpcTokenOwner.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/07/24.
//

import Foundation
extension SolanaService {

    class SolanaTokenAccount: Codable {
        let account: SolanaAccountData
        let pubkey: String

        enum CodingKeys: String, CodingKey {
            case account
            case pubkey
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            account = try container.decode(SolanaAccountData.self, forKey: .account)
            pubkey = try container.decode(String.self, forKey: .pubkey)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(account, forKey: .account)
            try container.encode(pubkey, forKey: .pubkey)
        }
    }

    class SolanaAccountData: Codable {
        let data: SolanaParsedData
        let executable: Bool
        let lamports: Int
        let owner: String
        let rentEpoch: UInt64
        let space: Int

        enum CodingKeys: String, CodingKey {
            case data
            case executable
            case lamports
            case owner
            case rentEpoch
            case space
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            data = try container.decode(SolanaParsedData.self, forKey: .data)
            executable = try container.decode(Bool.self, forKey: .executable)
            lamports = try container.decode(Int.self, forKey: .lamports)
            owner = try container.decode(String.self, forKey: .owner)
            rentEpoch = try container.decode(UInt64.self, forKey: .rentEpoch)
            space = try container.decode(Int.self, forKey: .space)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(data, forKey: .data)
            try container.encode(executable, forKey: .executable)
            try container.encode(lamports, forKey: .lamports)
            try container.encode(owner, forKey: .owner)
            try container.encode(rentEpoch, forKey: .rentEpoch)
            try container.encode(space, forKey: .space)
        }
    }

    class SolanaParsedData: Codable {
        let parsed: SolanaParsedInfo
        let program: String
        let space: Int

        enum CodingKeys: String, CodingKey {
            case parsed
            case program
            case space
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            parsed = try container.decode(SolanaParsedInfo.self, forKey: .parsed)
            program = try container.decode(String.self, forKey: .program)
            space = try container.decode(Int.self, forKey: .space)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(parsed, forKey: .parsed)
            try container.encode(program, forKey: .program)
            try container.encode(space, forKey: .space)
        }
    }

    class SolanaParsedInfo: Codable {
        let info: SolanaAccountInfo
        let type: String

        enum CodingKeys: String, CodingKey {
            case info
            case type
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            info = try container.decode(SolanaAccountInfo.self, forKey: .info)
            type = try container.decode(String.self, forKey: .type)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(info, forKey: .info)
            try container.encode(type, forKey: .type)
        }
    }

    class SolanaAccountInfo: Codable {
        let isNative: Bool
        let mint: String
        let owner: String
        let state: String
        let tokenAmount: SolanaTokenAmount

        enum CodingKeys: String, CodingKey {
            case isNative
            case mint
            case owner
            case state
            case tokenAmount
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isNative = try container.decode(Bool.self, forKey: .isNative)
            mint = try container.decode(String.self, forKey: .mint)
            owner = try container.decode(String.self, forKey: .owner)
            state = try container.decode(String.self, forKey: .state)
            tokenAmount = try container.decode(SolanaTokenAmount.self, forKey: .tokenAmount)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(isNative, forKey: .isNative)
            try container.encode(mint, forKey: .mint)
            try container.encode(owner, forKey: .owner)
            try container.encode(state, forKey: .state)
            try container.encode(tokenAmount, forKey: .tokenAmount)
        }
    }

    class SolanaTokenAmount: Codable {
        let amount: String
        let decimals: Int
        let uiAmount: Double
        let uiAmountString: String

        enum CodingKeys: String, CodingKey {
            case amount
            case decimals
            case uiAmount
            case uiAmountString
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            amount = try container.decode(String.self, forKey: .amount)
            decimals = try container.decode(Int.self, forKey: .decimals)
            uiAmount = try container.decode(Double.self, forKey: .uiAmount)
            uiAmountString = try container.decode(String.self, forKey: .uiAmountString)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(amount, forKey: .amount)
            try container.encode(decimals, forKey: .decimals)
            try container.encode(uiAmount, forKey: .uiAmount)
            try container.encode(uiAmountString, forKey: .uiAmountString)
        }
    }

}
