//
//  File.swift
//  
//
//  Created by Johnny Luo on 28/1/2024.
//

import Foundation

class Session: Codable{
    var SessionID: String
    var Participants:[String]
    
    init(SessionID: String, Participants: [String]) {
        self.SessionID = SessionID
        self.Participants = Participants
    }
}

struct Message: Codable {
    let SessionID: String
    let From: String
    let To: [String]
    let Body: String

    enum CodingKeys: String, CodingKey {
        case SessionID = "session_id"
        case From = "from"
        case To = "to"
        case Body = "body"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        SessionID = try container.decode(String.self, forKey: .SessionID)
        From = try container.decode(String.self, forKey: .From)
        To = try container.decode([String].self, forKey: .To)
        Body = try container.decode(String.self, forKey: .Body)
    }
}

class cacheItem: Codable{
    var messages: [Message]
    
    init(messages: [Message]) {
        self.messages = messages
    }

}
