//
//  CircleAPI.swift
//  VultisigApp
//

import Foundation

enum CircleAPI: TargetType {
    case getWallet(refId: String)
    case createWallet(request: CircleCreateWalletRequest)

    private static let vultisigProxyBaseURL = URL(string: "https://api.vultisig.com")!

    var baseURL: URL { Self.vultisigProxyBaseURL }

    var path: String {
        switch self {
        case .getWallet:
            return "/circle/wallet"
        case .createWallet:
            return "/circle/create"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getWallet:
            return .get
        case .createWallet:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .getWallet(let refId):
            return .requestParameters(["refId": refId], .urlEncoding)
        case .createWallet(let body):
            return .requestCodable(body, .jsonEncoding)
        }
    }

    var validationType: ValidationType {
        switch self {
        case .createWallet:
            // The proxy returns 401 distinctly from other errors so we can
            // surface `CircleApiError.unauthorized`; let the service decode
            // 200 + 401 bodies and map anything else to a generic error.
            return .customCodes([200, 401])
        default:
            return .successCodes
        }
    }
}

struct CircleCreateWalletRequest: Encodable {
    let idempotencyKey: String
    let accountType: String
    let name: String
    let owner: String

    enum CodingKeys: String, CodingKey {
        case idempotencyKey = "idempotency_key"
        case accountType = "account_type"
        case name
        case owner
    }
}
