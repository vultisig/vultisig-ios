//
//  TonAPI.swift
//  VultisigApp
//

import Foundation

enum TonAPI: TargetType {
    case addressInformation(address: String)
    case extendedAddressInformation(address: String)
    case jettonWallets(ownerAddress: String, jettonMasterAddress: String)
    case jettonWalletsByAddress(walletAddress: String)
    case jettonMasters(jettonAddress: String)
    case runGetMethod(address: String, method: String, stack: [[String]])
    case broadcastTransaction(boc: String)

    private static let vultisigProxyBaseURL = URL(string: "https://api.vultisig.com")!

    var baseURL: URL { Self.vultisigProxyBaseURL }

    var path: String {
        switch self {
        case .addressInformation:
            return "/ton/v3/addressInformation"
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
        switch self {
        case .addressInformation, .extendedAddressInformation, .jettonWallets, .jettonWalletsByAddress, .jettonMasters:
            return .get
        case .runGetMethod, .broadcastTransaction:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .addressInformation(let address):
            return .requestParameters(["address": address, "use_v2": "false"], .urlEncoding)
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
        switch self {
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
