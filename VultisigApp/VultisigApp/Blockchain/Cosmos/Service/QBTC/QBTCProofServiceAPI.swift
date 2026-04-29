//
//  QBTCProofServiceAPI.swift
//  VultisigApp
//
//  TargetType for the QBTC proof service (vultisig-proxied PLONK prover).
//  Mirrors vultisig-sdk/.../proofService.ts.
//

import Foundation

enum QBTCProofServiceAPI {
    case health
    case prove(ClaimProofRequest)
}

extension QBTCProofServiceAPI: TargetType {
    var baseURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: Endpoint.qbtcProofServiceBaseURL)!
    }

    var path: String {
        switch self {
        case .health:
            return "/health"
        case .prove:
            return "/prove"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .health:
            return .get
        case .prove:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .health:
            return .requestPlain
        case .prove(let request):
            return .requestCodable(request, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        switch self {
        case .health:
            return nil
        case .prove:
            return ["Content-Type": "application/json"]
        }
    }

    /// `/prove` runs a PLONK proof. The chain's prover takes minutes; the
    /// SDK uses a 300 s client deadline (`proofService.ts:4`). `/health` is
    /// fast and uses the default timeout.
    var timeoutInterval: TimeInterval {
        switch self {
        case .health:
            return 60
        case .prove:
            return QBTCClaimConfig.proofServiceTimeoutSeconds
        }
    }
}
