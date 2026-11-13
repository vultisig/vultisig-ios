//
//  FyndAPI.swift
//  VultisigApp
//

import Foundation

enum FyndAPI: TargetType {
    case quote(chain: String, body: FyndQuoteRequest, endpoint: FyndService.Endpoint)

    var baseURL: URL {
        switch self {
        case .quote(_, _, let endpoint):
            return endpoint.baseURL
        }
    }

    var path: String {
        switch self {
        case .quote(let chain, _, _):
            return "/v1/\(chain)/quote"
        }
    }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        switch self {
        case .quote(_, let body, _):
            return .requestCodable(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        var headers = [
            "accept": "application/json",
            "content-type": "application/json"
        ]
        if case .quote(_, _, let endpoint) = self, let apiKey = endpoint.apiKey {
            // Fynd takes the raw key, no `Bearer` prefix. Only the debug
            // direct-key endpoint carries one; release builds go through the
            // Vultisig proxy, which injects the key server-side.
            headers["Authorization"] = apiKey
        }
        return headers
    }

    var validationType: ValidationType { .customCodes([200]) }

    var timeoutInterval: TimeInterval { 15 }
}
