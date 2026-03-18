//
//  RippleTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

struct RippleTransactionStatusResponse: Codable {
    let result: RippleResult?
    let error: String?  // "txnNotFound" when transaction doesn't exist
    let error_code: Int?
    let error_message: String?
    let status: String?  // "error" when there's an error

    struct RippleResult: Codable {
        let Account: String?
        let Fee: String?
        let Sequence: Int?
        let validated: Bool?
        let ledger_index: Int?
        let meta: RippleMeta?
        let hash: String?

        // Optional fields for different transaction types
        let Destination: String?
        let Amount: RippleAmount?

        // Error fields when result contains an error
        let status: String?  // "error" when there's an error
        let error: String?  // "notImpl", "txnNotFound", etc.
        let error_code: Int?
        let error_message: String?
        let request: RippleRequest?  // Request object containing transaction field
    }

    struct RippleRequest: Codable {
        let transaction: String?  // May contain error message instead of hash
        let api_version: Int?
        let binary: Bool?
        let command: String?
    }

    struct RippleMeta: Codable {
        let TransactionResult: String  // "tesSUCCESS", "tecUNFUNDED_PAYMENT", etc.
        let TransactionIndex: Int?
    }

    // Amount can be either a string (XRP drops) or an object (issued currency)
    enum RippleAmount: Codable {
        case drops(String)
        case issuedCurrency(IssuedCurrency)

        struct IssuedCurrency: Codable {
            let currency: String
            let value: String
            let issuer: String
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let drops = try? container.decode(String.self) {
                self = .drops(drops)
            } else if let issued = try? container.decode(IssuedCurrency.self) {
                self = .issuedCurrency(issued)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Amount must be either a string or an issued currency object"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .drops(let value):
                try container.encode(value)
            case .issuedCurrency(let currency):
                try container.encode(currency)
            }
        }
    }
}
