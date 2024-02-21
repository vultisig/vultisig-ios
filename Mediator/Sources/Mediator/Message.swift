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
    let header: MessageHeader
    let body: String
}

public struct HelloMessage: Codable {
    let clientKey: String
}

public struct SessionMessage: Codable {
    let clientKey: String
    let sessionID: String
}

public struct StartTSSMessage: Codable {
    let sessionID: String
    let message: Message
}
