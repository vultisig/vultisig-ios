//
//  CardanoAPI.swift
//  VultisigApp
//

import Foundation

enum CardanoAPI: TargetType {
    case getAddressInfo(address: String)
    case getTip
    case broadcastTransaction(cborHex: String)

    var baseURL: URL {
        switch self {
        case .getAddressInfo, .getTip:
            return URL(string: Endpoint.cardanoServiceRpc)!
        case .broadcastTransaction:
            return Endpoint.cardanoBroadcast()
        }
    }

    var path: String {
        switch self {
        case .getAddressInfo:
            return "/address_info"
        case .getTip:
            return "/tip"
        case .broadcastTransaction:
            return ""
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getTip:
            return .get
        case .getAddressInfo, .broadcastTransaction:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .getAddressInfo(let address):
            return .requestParameters(["_addresses": [address]], .jsonEncoding)
        case .getTip:
            return .requestPlain
        case .broadcastTransaction(let cborHex):
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "submitTransaction",
                "params": [
                    "transaction": ["cbor": cborHex]
                ],
                "id": 1
            ]
            return .requestParameters(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }
}
