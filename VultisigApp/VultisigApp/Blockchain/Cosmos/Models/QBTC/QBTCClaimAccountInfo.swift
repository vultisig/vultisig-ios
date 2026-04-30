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

/// Response shape for `GET /cosmos/auth/v1beta1/accounts?pagination.limit=1000`.
/// Used to scan for the highest-numbered existing account so first-claim flows
/// can predict the assigned `account_number` for their fresh address. The
/// chain's `FreeClaimDecorator` atomically increments the global counter, so
/// the next assignment is `max(account_number) + 1`.
///
/// Account-type polymorphism: the `accounts` array mixes `BaseAccount`s
/// (account_number at the top level) with `ModuleAccount`s like fee_collector
/// (account_number nested inside `base_account`). The custom decoder normalises
/// both into `Account.accountNumber`. Both share the global account-number
/// namespace so they all matter for the max calculation.
struct QBTCAccountsListResponse: Codable {
    let accounts: [Account]
    let pagination: Pagination?

    struct Account: Codable {
        let accountNumber: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let direct = try container.decodeIfPresent(String.self, forKey: .accountNumber) {
                self.accountNumber = direct
                return
            }
            if let base = try container.decodeIfPresent(BaseAccount.self, forKey: .baseAccount) {
                self.accountNumber = base.accountNumber
                return
            }
            self.accountNumber = "0"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(accountNumber, forKey: .accountNumber)
        }

        enum CodingKeys: String, CodingKey {
            case accountNumber = "account_number"
            case baseAccount = "base_account"
        }

        struct BaseAccount: Codable {
            let accountNumber: String

            enum CodingKeys: String, CodingKey {
                case accountNumber = "account_number"
            }
        }
    }

    struct Pagination: Codable {
        let nextKey: String?

        enum CodingKeys: String, CodingKey {
            case nextKey = "next_key"
        }
    }
}
