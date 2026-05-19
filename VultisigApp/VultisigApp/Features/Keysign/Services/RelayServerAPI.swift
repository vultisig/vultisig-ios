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
        /// `POST {server}/{sessionID}` with `[localPartyId]` — the
        /// "I'm here" signal a participant POSTs after joining a session.
        case registerAsParticipant(sessionID: String, body: Data)
        /// `POST {server}/start/{sessionID}` with the participant list —
        /// the relay's "everyone has joined; start the keysign" trigger.
        case startSession(sessionID: String, body: Data)
        /// `GET {server}/start/{sessionID}` — peers poll this until the
        /// initiator has POSTed the participant list.
        case pollSessionStart(sessionID: String)
    }

    var path: String {
        switch endpoint {
        case .getParticipants(let sessionID), .registerAsParticipant(let sessionID, _):
            return "/\(sessionID)"
        case .startSession(let sessionID, _), .pollSessionStart(let sessionID):
            return "/start/\(sessionID)"
        }
    }

    var method: HTTPMethod {
        switch endpoint {
        case .getParticipants, .pollSessionStart:
            return .get
        case .registerAsParticipant, .startSession:
            return .post
        }
    }

    var task: HTTPTask {
        switch endpoint {
        case .getParticipants, .pollSessionStart:
            return .requestPlain
        case .registerAsParticipant(_, let body), .startSession(_, let body):
            return .requestData(body)
        }
    }

    var headers: [String: String]? {
        switch endpoint {
        case .registerAsParticipant, .startSession:
            return ["Content-Type": "application/json"]
        case .getParticipants, .pollSessionStart:
            return nil
        }
    }

    var validationType: ValidationType {
        switch endpoint {
        case .getParticipants, .pollSessionStart:
            // The relay returns 404 while a session is still warming up;
            // observe that status distinctly rather than treat it as an error.
            return .customCodes([200, 404])
        case .registerAsParticipant, .startSession:
            return .successCodes
        }
    }
}
