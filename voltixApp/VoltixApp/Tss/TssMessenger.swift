//
//  TssMessenger.swift
//  VoltixApp
//

import Foundation
import Tss
import CryptoKit
import OSLog
import Mediator

private let logger = Logger(subsystem: "keygen", category: "tss")
final class TssMessengerImpl: NSObject, TssMessengerProtocol {
    let mediatorUrl: String
    let sessionID: String
    
    init(mediatorUrl: String, sessionID: String) {
        self.mediatorUrl = mediatorUrl
        self.sessionID = sessionID
    }
    
    func getMessageBodyHash(msg: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(msg.utf8))
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
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
        logger.info("from:\(fromParty),to:\(to)")
        let urlString = "\(self.mediatorUrl)/message/\(self.sessionID)"
        let url = URL(string: urlString)
        guard let url else {
            logger.error("URL can't be construct from: \(urlString)")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let msg = Message(session_id: sessionID, from: fromParty, to: [to], body: body, hash: getMessageBodyHash(msg: body))
        do {
            let jsonEncode = JSONEncoder()
            let encodedBody = try jsonEncode.encode(msg)
            req.httpBody = encodedBody
        } catch {
            logger.error("fail to encode body into json string,\(error)")
            return
        }
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err {
                logger.error("fail to send message,error:\(err)")
                return
            }
            guard let resp = resp as? HTTPURLResponse, (200...299).contains(resp.statusCode) else {
                logger.error("invalid response code")
                return
            }
            logger.debug("send message to mediator server successfully")
        }.resume()
    }
    }
