//
//  RelayServerAPI.swift
//  VultisigApp
//

import Foundation

/// TargetType for the TSS relay server (`serverAddr/sessionID` endpoints).
///
/// The relay host isn't known at compile time — it comes from the vault's
/// mediator config — so this takes a caller-supplied `baseURL` and an
/// `endpoint` case describing the path/method/body.
struct RelayServerAPI: TargetType {
    let baseURL: URL
    let endpoint: Endpoint

    enum Endpoint {
        case getParticipants(sessionID: String)
    }

    var path: String {
        switch endpoint {
        case .getParticipants(let sessionID):
            return "/\(sessionID)"
        }
    }

    var method: HTTPMethod {
        switch endpoint {
        case .getParticipants:
            return .get
        }
    }

    var task: HTTPTask {
        .requestPlain
    }

    var validationType: ValidationType {
        // The relay returns 404 while a session is still warming up; we want
        // to observe that status distinctly rather than treat it as an error.
        .customCodes([200, 404])
    }
}
