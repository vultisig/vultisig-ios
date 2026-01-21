//
//  KeygenVerify.swift
//  VultisigApp
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
            _ = try await Utils.asyncPostRequest(urlString: urlString, headers: nil, body: jsonData)
        } catch {
            self.logger.error("Failed to send request to mediator, error:\(error)")
        }
    }
    
    func checkCompletedParties() async -> Bool {
        let urlString = "\(serverAddr)/complete/\(sessionID)"
        let start = Date()
        repeat {
            do {
                let result = try await Utils.asyncGetRequest(urlString: urlString, headers: nil)
                if !result.isEmpty {
                    let decoder = JSONDecoder()
                    let peers = try decoder.decode([String].self, from: result)
                    if Set(self.keygenCommittee).isSubset(of: Set(peers)) {
                        self.logger.info("all parties have completed keygen successfully")
                        return true
                    }
                }
                try await Task.sleep(for: .seconds(1)) // backoff for 1 second
            } catch {
                self.logger.error("Failed to decode response to JSON: \(error)")
            }
            
        } while (Date().timeIntervalSince(start) < 60) // set timeout to 1 minutes
        return false
    }
}
