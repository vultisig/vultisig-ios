//
//  TonAPI.swift
//  VultisigApp
//

import Foundation

/// Pure `TargetType` for the TON Center endpoints consumed by `TonService`.
/// The host is baked in at construction by the service (see `TonService.api`);
/// this value never consults global state.
///
/// The default host is the Vultisig proxy (`api.vultisig.com`), so when no
/// override is set behavior is byte-identical to before — including the
/// heterogeneous per-case `/ton/v2` + `/ton/v3` path scheme. An override only
/// swaps the host while keeping those TON Center paths unchanged, so a real
/// TON Center node (same `/v2|/v3` scheme) works as-is.
struct TonAPI: TargetType {
    enum Endpoint {
        case addressInformation(address: String)
        case wallet(address: String)
        case extendedAddressInformation(address: String)
        case jettonWallets(ownerAddress: String, jettonMasterAddress: String)
        case jettonWalletsByAddress(walletAddress: String)
        case jettonMasters(jettonAddress: String)
        case runGetMethod(address: String, method: String, stack: [[String]])
        case broadcastTransaction(boc: String)
    }

    /// Default TON host (Vultisig proxy).
    static let defaultHost = URL(string: "https://api.vultisig.com")!

    let endpoint: Endpoint
    /// The resolved TON host (override-aware), baked in by the service.
    let host: URL

    init(_ endpoint: Endpoint, host: URL = TonAPI.defaultHost) {
        self.endpoint = endpoint
        self.host = host
    }

    var baseURL: URL { host }

    var path: String {
        switch endpoint {
        case .addressInformation:
            return "/ton/v3/addressInformation"
        case .wallet:
            return "/ton/v3/wallet"
        case .extendedAddressInformation:
            return "/ton/v2/getExtendedAddressInformation"
        case .jettonWallets, .jettonWalletsByAddress:
            return "/ton/v3/jetton/wallets"
        case .jettonMasters:
            return "/ton/v3/jetton/masters"
        case .runGetMethod:
            return "/ton/v2/runGetMethod"
        case .broadcastTransaction:
            return "/ton/v2/sendBocReturnHash"
        }
    }

    var method: HTTPMethod {
        switch endpoint {
        case .addressInformation, .wallet, .extendedAddressInformation, .jettonWallets, .jettonWalletsByAddress, .jettonMasters:
            return .get
        case .runGetMethod, .broadcastTransaction:
            return .post
        }
    }

    var task: HTTPTask {
        switch endpoint {
        case .addressInformation(let address):
            return .requestParameters(["address": address, "use_v2": "false"], .urlEncoding)
        case .wallet(let address):
            return .requestParameters(["address": address], .urlEncoding)
        case .extendedAddressInformation(let address):
            return .requestParameters(["address": address], .urlEncoding)
        case .jettonWallets(let owner, let master):
            return .requestParameters(["owner_address": owner, "jetton_master_address": master], .urlEncoding)
        case .jettonWalletsByAddress(let walletAddress):
            return .requestParameters(["address": walletAddress, "limit": 1], .urlEncoding)
        case .jettonMasters(let jettonAddress):
            return .requestParameters(["address": jettonAddress, "limit": 1], .urlEncoding)
        case .runGetMethod(let address, let method, let stack):
            return .requestCodable(TonRunGetMethodRequest(address: address, method: method, stack: stack), .jsonEncoding)
        case .broadcastTransaction(let boc):
            return .requestCodable(TonBroadcastRequest(boc: boc), .jsonEncoding)
        }
    }

    var validationType: ValidationType {
        switch endpoint {
        case .broadcastTransaction:
            // TON returns HTTP 500 with a body containing "duplicate message"
            // when a sibling TSS device already broadcast the same transaction;
            // we need the body to recognize that as a soft-success.
            return .customCodes([200, 500])
        default:
            return .successCodes
        }
    }
}

// MARK: - Request bodies

struct TonBroadcastRequest: Encodable {
    let boc: String
}

struct TonRunGetMethodRequest: Encodable {
    let address: String
    let method: String
    let stack: [[String]]
}

// MARK: - Response types

struct TonAddressInformation: Decodable {
    let balance: String?
    let status: String?
}

/// Response from the Vultisig proxy `/ton/v3/wallet` endpoint. Same shape the
/// Windows client / SDK `getTonBalance` reads: the native `balance` plus any
/// nominator-pool staking positions. `pools` is omitted by the backend when the
/// wallet has no staked positions, so it decodes as an optional and the service
/// normalizes a missing array to empty.
struct TonWalletInformation: Decodable {
    let balance: String?
    let pools: [TonWalletPool]?
}

/// A single nominator-pool staking position. `address` is the pool contract
/// (raw `0:…` form from the backend) and `amount` is the staked balance in
/// nanotons, as a decimal string.
struct TonWalletPool: Decodable {
    let address: String
    let amount: String
}

struct TonExtendedAddressInformation: Decodable {
    let result: ExtendedResult?

    struct ExtendedResult: Decodable {
        let accountState: AccountState?

        enum CodingKeys: String, CodingKey {
            case accountState = "account_state"
        }

        struct AccountState: Decodable {
            let seqno: UInt64?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // TON's extendedAddressInformation can return seqno as either a
                // JSON number or a string depending on account state; accept both.
                if let value = try? container.decode(UInt64.self, forKey: .seqno) {
                    seqno = value
                } else if let value = try? container.decode(String.self, forKey: .seqno) {
                    seqno = UInt64(value)
                } else {
                    seqno = nil
                }
            }

            private enum CodingKeys: String, CodingKey {
                case seqno
            }
        }
    }
}
