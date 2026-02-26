//
//  NotificationAPI.swift
//  VultisigApp
//

import Foundation

enum NotificationAPI: TargetType {
    case register(payload: DeviceRegistrationRequest)
    case unregister(payload: DeviceUnregisterRequest)
    case isVaultRegistered(vaultId: String)
    case notify(payload: NotifyRequest)

    var baseURL: URL {
        URL(string: Endpoint.vultisigNotification)!
    }

    var path: String {
        switch self {
        case .register:
            return "/register"
        case .unregister:
            return "/unregister"
        case .isVaultRegistered(let vaultId):
            return "/vault/\(vaultId)"
        case .notify:
            return "/notify"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .register, .notify:
            return .post
        case .unregister:
            return .delete
        case .isVaultRegistered:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .register(let payload):
            return .requestCodable(payload, .jsonEncoding)
        case .unregister(let payload):
            return .requestCodable(payload, .jsonEncoding)
        case .isVaultRegistered:
            return .requestPlain
        case .notify(let payload):
            return .requestCodable(payload, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["X-Client-ID": "vultisig"]
    }
}
