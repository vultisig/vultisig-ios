//
//  File.swift
//  
//
//  Created by Johnny Luo on 28/1/2024.
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
    let session_id: String
    let from: String
    let to: [String]
    let body: String
}

final class cacheItem: Codable{
    var messages: [Message]
    
    init(messages: [Message]) {
        self.messages = messages
    }
}
