//
//  KeysignVerify.swift
//  VultisigApp
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
        do {
            let jsonData = try sig.getJson()
            let header = ["message_id": message]
            _ = try await Utils.asyncPostRequest(urlString: urlString, headers: header, body: jsonData)
        } catch {
            self.logger.error("Failed to send request to mediator, error:\(error)")
        }
    }

    func checkKeySignComplete(message: String) async -> TssKeysignResponse? {
        do {
            let result = try await Utils.asyncGetRequest(urlString: urlString, headers: ["message_id": message])
            if !result.isEmpty {
                let resp = try TssKeysignResponse().fromJson(json: result)
                return resp
            }
        } catch {
            self.logger.error("Failed to decode response to JSON: \(error)")
        }
        return nil
    }
}
