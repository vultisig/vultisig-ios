//
//  KeysignVerify.swift
//  VoltixApp
//
//  Created by Johnny Luo on 24/4/2024.
//

import Foundation
import OSLog
import Tss

class KeysignVerify: ObservableObject {
    private let logger = Logger(subsystem: "keysign-verify", category: "communication")
    let serverAddr: String
    let sessionID: String
    let urlString: String
    
    init(serverAddr: String, sessionID: String) {
        self.serverAddr = serverAddr
        self.sessionID = sessionID
        self.urlString = "\(self.serverAddr)/complete/\(self.sessionID)/keysign"
    }
    
    func markLocalPartyKeysignComplete(message: String, sig: TssKeysignResponse) async {
        print(self.urlString)
        do {
            let jsonData = try sig.getJson()
            let header = ["message_id" : message]
            _ = try await Utils.asyncPostRequest(urlString: urlString, headers: header, body: jsonData)
        } catch {
            self.logger.error("Failed to send request to mediator, error:\(error)")
        }
    }
    
    func checkKeySignComplete(message: String) async -> TssKeysignResponse? {
        print(self.urlString)
        do {
            let result = try await Utils.asyncGetRequest(urlString: urlString, headers: ["message_id":message])
            if !result.isEmpty {
                print("res: \( String(data:result,encoding: .utf8) ?? "")")
                let rawData = try JSONDecoder().decode(String.self, from: result)
                if let jsonData = rawData.data(using: .utf8) {
                    let resp = try TssKeysignResponse().fromJson(json: jsonData)
                    return resp
                }
            }
        } catch {
            self.logger.error("Failed to decode response to JSON: \(error)")
        }
        return nil
    }
}

