//
//  DKLSMessenger.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/12/2024.
//

import Foundation
import Mediator
import OSLog
import CryptoKit

private let logger = Logger(subsystem: "messenger", category: "dkls")
final class DKLSMessenger {
    let mediatorURL: String
    let sessionID: String
    let messageID: String?
    let encryptionKeyHex: String
    var counter: Int64 = 1
    
    init(mediatorUrl: String,
         sessionID: String,
         messageID: String?,
         encryptionKeyHex: String) {
        self.mediatorURL = mediatorUrl
        self.sessionID = sessionID
        self.messageID = messageID
        self.encryptionKeyHex = encryptionKeyHex
    }
    
    func uploadSetupMessage(message: String,_ additionalHeader: String?) async throws {
        let urlString = "\(self.mediatorURL)/setup-message/\(self.sessionID)"
        let url = URL(string: urlString)
        guard let url else {
            throw HelperError.runtimeError("URL can't be construct from: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let messageID = self.messageID {
            req.setValue(messageID, forHTTPHeaderField: "message_id")
        }
        // additionalHeader override the message_id
        // currently additionalHeader only used in DKLS reshare
        if let additionalHeader {
            req.setValue(additionalHeader, forHTTPHeaderField: "message-id")
        }
        
        let encryptedBody = message.aesEncryptGCM(key: self.encryptionKeyHex)
        guard let encryptedBody else {
            throw HelperError.runtimeError("fail to encrypt message body")
        }
        req.httpBody = encryptedBody.data(using: .utf8)
        let (_,resp) = try await URLSession.shared.data(for: req)
        if let httpResponse = resp as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                throw HelperError.runtimeError("fail to setup message to relay server,status:\(httpResponse.statusCode)")
            }
        }
    }
    
    func downloadSetupMessageWithRetry(_ additionalHeader: String?) async throws -> String {
        var attempt = 0
        repeat {
            do {
                return try await downloadSetupMessage(additionalHeader)
            } catch {
                print("fail to download setup message,error \(error), attempt: \(attempt)")
                //backoff 1s
                try await Task.sleep(for: .seconds(1))
            }
            attempt = attempt + 1
        } while attempt < 10
        
        throw HelperError.runtimeError("fail to download setup message after 10 retries")
    }
    
    func downloadSetupMessage(_ additionalHeader: String?) async throws -> String {
        let urlString = "\(self.mediatorURL)/setup-message/\(self.sessionID)"
        let url = URL(string: urlString)
        guard let url else {
            throw HelperError.runtimeError("URL can't be construct from: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let messageID = self.messageID {
            req.setValue(messageID, forHTTPHeaderField: "message_id")
        }
        if let additionalHeader {
            req.setValue(additionalHeader, forHTTPHeaderField: "message-id")
        }
        let (data,resp) = try await URLSession.shared.data(for: req)
        if let httpResponse = resp as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                throw HelperError.runtimeError("fail to download setup message from relay server,status:\(httpResponse.statusCode)")
            }
        }
        let setupMsg = String(data: data,encoding: .utf8)
        guard let setupMsg else {
            throw HelperError.runtimeError("fail to convert setup message")
        }
        if let result = setupMsg.aesDecryptGCM(key: self.encryptionKeyHex) {
            return result
        }
        throw HelperError.runtimeError("fail to decrypt setup message")
    }
    
    func send(_ fromParty: String?, to: String?, body: String?) async throws {
        guard let fromParty else {
            logger.error("from is nil")
            return
        }
        guard let to else {
            logger.error("to is nil")
            return
        }
        guard let body else {
            logger.error("body is nil")
            return
        }
        let urlString = "\(self.mediatorURL)/message/\(self.sessionID)"
        let url = URL(string: urlString)
        guard let url else {
            logger.error("URL can't be construct from: \(urlString)")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let messageID = self.messageID {
            req.setValue(messageID, forHTTPHeaderField: "message_id")
        }
        
        let encryptedBody = body.aesEncryptGCM(key: self.encryptionKeyHex)
        guard let encryptedBody else {
            logger.error("fail to encrypt message body")
            return
        }
        let msg = Message(session_id: sessionID,
                          from: fromParty,
                          to: [to],
                          body: encryptedBody,
                          hash: Utils.getMessageBodyHash(msg: body),
                          sequenceNo: self.counter)
        self.counter += 1
        do {
            let jsonEncode = JSONEncoder()
            let encodedBody = try jsonEncode.encode(msg)
            req.httpBody = encodedBody
        } catch {
            logger.error("fail to encode body into json string,\(error)")
            return
        }
        for _ in 0...3 {
            do {
                let (_,resp) = try await URLSession.shared.data(for: req)
                if let httpResponse = resp as? HTTPURLResponse {
                    if !(200...299).contains(httpResponse.statusCode) {
                        logger.error("fail to send message to relay server,status:\(httpResponse.statusCode)")
                        continue // retry
                    }
                }
                logger.info("send message (\(msg.hash) to (\(msg.to)) successfully, sequenceNo:\(msg.sequence_no)")
                return
            }
            catch {
                logger.error("fail to send message,error:\(error)")
            }
        }
    }
}
