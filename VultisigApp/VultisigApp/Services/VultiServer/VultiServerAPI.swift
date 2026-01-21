//
//  VultiServerAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/08/2025.
//

import Foundation

enum VultiServerAPI: TargetType {
    case resendVaultShare(request: ResendVaultShareRequest)

    var baseURL: URL {
        return URL(string: "https://api.vultisig.com")!
    }

    var path: String {
        switch self {
        case .resendVaultShare:
            return "/vault/resend"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .resendVaultShare:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .resendVaultShare(let request):
            return .requestCodable(request, .jsonEncoding)
        }
    }
}
