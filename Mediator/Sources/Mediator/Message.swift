//
//  File.swift
//  
//
//  Created by Johnny Luo on 28/1/2024.
//

import Foundation

class Session: Codable {
    var SessionID: String
    var Participants: [String]
    
    init(SessionID: String, Participants: [String]) {
        self.SessionID = SessionID
        self.Participants = Participants
    }
}

struct Message: Codable {
    let session_id: String
    let from: String
    let to: [String]
    let body: String
}

class cacheItem: Codable{
    var messages: [Message]
    
    init(messages: [Message]) {
        self.messages = messages
    }
}
