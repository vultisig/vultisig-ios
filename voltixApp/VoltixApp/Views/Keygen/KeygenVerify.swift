//
//  KeygenVerify.swift
//  VoltixApp
//
//  Created by Johnny Luo on 12/4/2024.
//

import Foundation
import OSLog

class KeygenVerify: ObservableObject {
    private let logger = Logger(subsystem: "keygen-verify", category: "communication")
    let serverAddr: String
    let sessionID: String
    let localPartyID: String
    let keygenCommittee: [String]
    
    init(serverAddr: String, sessionID: String, localPartyID: String, keygenCommittee: [String]) {
        self.serverAddr = serverAddr
        self.sessionID = sessionID
        self.localPartyID = localPartyID
        self.keygenCommittee = keygenCommittee
    }
    
    func markLocalPartyComplete() async {
        let urlString = "\(self.serverAddr)/complete/\(self.sessionID)"
        let body = [self.localPartyID]
        do {
            let jsonData = try JSONEncoder().encode(body)
            _ = try await Utils.asyncPostRequest(urlString: urlString, headers: [String:String](), body: jsonData)
        } catch {
            self.logger.error("Failed to send request to mediator, error:\(error)")
        }
    }
    
    func checkCompletedParties() async -> Bool {
        let urlString = "\(serverAddr)/\(sessionID)"
        let start = Date()
        repeat{
            do {
                let result = try await Utils.asyncGetRequest(urlString: urlString, headers: [String:String]())
                if !result.isEmpty {
                    let decoder = JSONDecoder()
                    let peers = try decoder.decode([String].self, from: result)
                    if Set(peers).isSubset(of: Set(self.keygenCommittee)) {
                        return true
                    }
                }
            } catch {
                self.logger.error("Failed to decode response to JSON: \(error)")
            }
        } while (Date().timeIntervalSince(start) < 120) // set timeout to 2 minutes
        return false
    }
}
