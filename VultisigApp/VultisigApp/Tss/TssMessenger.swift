//
//  TssMessenger.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import Mediator
import OSLog
import Tss

private let logger = Logger(subsystem: "messenger", category: "tss")
final class TssMessengerImpl: NSObject, TssMessengerProtocol {
    let mediatorUrl: String
    let sessionID: String
    // messageID will be used during keysign , because for UTXO related chains , it usually need to sign multiple UTXOs
    // at the same time , add message id here to avoid messages belongs to differet keysign message messed with each other
    let messageID: String?
    let encryptionKeyHex: String
    let isKeygen: Bool
    var vaultPubKey = ""
    let encryptGCM: Bool

    var counter: Int64 = 1
    init(mediatorUrl: String,
         sessionID: String,
         messageID: String?,
         encryptionKeyHex: String,
         vaultPubKey: String,
         isKeygen: Bool,
         encryptGCM: Bool) {
        self.mediatorUrl = mediatorUrl
        self.sessionID = sessionID
        self.messageID = messageID
        self.encryptionKeyHex = encryptionKeyHex
        self.vaultPubKey = vaultPubKey
        self.isKeygen = isKeygen
        self.encryptGCM = encryptGCM
    }

    func send(_ fromParty: String?, to: String?, body: String?) throws {
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
        let urlString = "\(self.mediatorUrl)/message/\(self.sessionID)"
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
        if isKeygen {
            req.setValue("vultisig", forHTTPHeaderField: "keygen")
        }
        var encryptedBody: String? = nil
        if self.encryptGCM {
            print("decrypt with AES+GCM")
            encryptedBody = body.aesEncryptGCM(key: self.encryptionKeyHex)
        } else {
            print("decrypt with AES+CBC")
            encryptedBody = body.aesEncrypt(key: self.encryptionKeyHex)
        }
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
        let retry = 3
        self.sendWithRetry(req: req, msg: msg, retry: retry)
    }

    func sendWithRetry(req: URLRequest, msg: Message, retry: Int) {
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err {
                logger.error("fail to send message,error:\(err)")
                if retry == 0 {
                    return
                } else {
                    self.sendWithRetry(req: req, msg: msg, retry: retry - 1)
                }
            }
            guard let resp = resp as? HTTPURLResponse, (200 ... 299).contains(resp.statusCode) else {
                logger.error("invalid response code")
                return
            }
            logger.debug("send message (\(msg.hash) to (\(msg.to)) successfully")
        }.resume()
    }
}
