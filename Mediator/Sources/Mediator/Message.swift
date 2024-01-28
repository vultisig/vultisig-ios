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

class Message: Codable {
    let SessionID: String
    let From: String
    let To: [String]
    let Body: String
}
