//
//  SuiRPCResponse.swift
//  VultisigApp
//

import Foundation

/// The `error` member of a Sui JSON-RPC envelope. Sui answers HTTP 200 and puts
/// the refusal in the body, so this — not the status code — is the signal that
/// the node understood the request and declined it.
struct SuiRPCError: Decodable, Equatable {
    let code: Int?
    let message: String
}

/// `suix_getReferenceGasPrice` — the result is a decimal string.
struct SuiReferenceGasPriceResponse: Decodable {
    let result: String?
    let error: SuiRPCError?
}

/// `sui_executeTransactionBlock`.
struct SuiExecuteTransactionResponse: Decodable {
    struct Result: Decodable {
        let digest: String?
    }

    let result: Result?
    let error: SuiRPCError?
}

/// `sui_dryRunTransactionBlock`. Only the fields the fee estimate reads are
/// modelled; the full effects object is large and the rest is unused.
struct SuiDryRunResponse: Decodable {
    struct Result: Decodable {
        let effects: Effects?
    }

    struct Effects: Decodable {
        let status: Status?
        let gasUsed: GasUsed?
    }

    struct Status: Decodable {
        let status: String?
        let error: String?
    }

    struct GasUsed: Decodable {
        let computationCost: String?
        let storageCost: String?
    }

    let result: Result?
    let error: SuiRPCError?
}
