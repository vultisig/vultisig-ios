//
//  QBTCClaimAccountInfo.swift
//  VultisigApp
//
//  Combined account + latest-block info needed to assemble the QBTC
//  claim cosmos transaction. Mirrors vultisig-sdk/.../getQbtcAccountInfo.ts.
//

import Foundation

/// Account state and timeout window needed when building a claim TxRaw.
/// `accountNumber=0, sequence=0` is the legitimate "fresh account" state —
/// the claim is often the first transaction for a QBTC address.
struct QBTCClaimAccountInfo: Equatable {
    let accountNumber: UInt64
    let sequence: UInt64
    /// Latest block height as reported by the chain.
    let latestBlockHeight: UInt64
    /// Tx timeout in nanoseconds since epoch — `latestBlockTimeNs + 10 minutes`.
    let timeoutNs: UInt64
}

// MARK: - Wire-format DTOs (private to the service layer)

struct QBTCAuthAccountResponse: Codable {
    let account: Account?

    struct Account: Codable {
        let accountNumber: String
        let sequence: String

        enum CodingKeys: String, CodingKey {
            case accountNumber = "account_number"
            case sequence
        }
    }
}

struct QBTCLatestBlockResponse: Codable {
    let block: Block

    struct Block: Codable {
        let header: Header

        struct Header: Codable {
            let height: String
            let time: String
        }
    }
}

struct QBTCParamResponse: Codable {
    let param: Param

    struct Param: Codable {
        let key: String
        let value: String
    }
}
