//
//  File.swift
//

import Foundation

final class Session: Codable {
    var SessionID: String
    var Participants: [String]

    init(SessionID: String, Participants: [String]) {
        self.SessionID = SessionID
        self.Participants = Participants
    }
}

public struct Message: Codable {
    public let session_id: String
    public let from: String
    public let to: [String]
    public let body: String
    public let hash: String
    public let sequenceNo: Int64

    public init(session_id: String, from: String, to: [String], body: String, hash: String, sequenceNo: Int64) {
        self.session_id = session_id
        self.from = from
        self.to = to
        self.body = body
        self.hash = hash
        self.sequenceNo = sequenceNo
    }
}

public enum MessageHeader: Codable {
    case HelloMessage
    case StartSession
    case JoinSession // join a session
    case DropSession // drop from a session
    case EndSession
    case TSSRouting
    case StartTSS
}

public struct WebsocketMessage: Codable {
    public let header: MessageHeader
    public let body: String
    public init(header: MessageHeader, body: String) {
        self.header = header
        self.body = body
    }
}

public struct HelloMessage: Codable {
    public let clientKey: String
    public init(clientKey: String) {
        self.clientKey = clientKey
    }
}

public struct SessionMessage: Codable {
    public let clientKey: String
    public let sessionID: String
    
    public init(clientKey: String, sessionID: String) {
        self.clientKey = clientKey
        self.sessionID = sessionID
    }
}

public struct StartTSSMessage: Codable {
    public let sessionID: String
    public let committee: [String]
    public init(sessionID: String, committee: [String]) {
        self.sessionID = sessionID
        self.committee = committee
    }
}

public struct TSSRoutingMessage: Codable {
    public let sessionID: String
    public let to: String
    public let message: Message
    public init(sessionID: String, to: String, message: Message) {
        self.sessionID = sessionID
        self.to = to
        self.message = message
    }
}
