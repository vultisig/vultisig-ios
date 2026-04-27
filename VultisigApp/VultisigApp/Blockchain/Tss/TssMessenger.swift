//
//  TssMessenger.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import Mediator
import OSLog
import Tss

private let logger = Logger(subsystem: "com.vultisig.app", category: "net-tss-messenger")
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
    private let httpClient: HTTPClientProtocol

    var counter: Int64 = 1
    init(mediatorUrl: String,
         sessionID: String,
         messageID: String?,
         encryptionKeyHex: String,
         vaultPubKey: String,
         isKeygen: Bool,
         encryptGCM: Bool,
         httpClient: HTTPClientProtocol = HTTPClient()) {
        self.mediatorUrl = mediatorUrl
        self.sessionID = sessionID
        self.messageID = messageID
        self.encryptionKeyHex = encryptionKeyHex
        self.vaultPubKey = vaultPubKey
        self.isKeygen = isKeygen
        self.encryptGCM = encryptGCM
        self.httpClient = httpClient
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
        guard let baseURL = URL(string: mediatorUrl) else {
            logger.error("URL can't be construct from: \(self.mediatorUrl)")
            return
        }

        let encryptedBody: String?
        if self.encryptGCM {
            encryptedBody = body.aesEncryptGCM(key: self.encryptionKeyHex)
        } else {
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

        // The TssMessenger Objective-C protocol is synchronous (Go callback),
        // so we kick the HTTP work onto a detached Task and let it retry
        // independently — preserving the original fire-and-forget semantics.
        let httpClient = self.httpClient
        let messageID = self.messageID
        let isKeygen = self.isKeygen
        let sessionID = self.sessionID
        Task.detached {
            await Self.sendWithRetry(
                httpClient: httpClient,
                baseURL: baseURL,
                sessionID: sessionID,
                msg: msg,
                messageID: messageID,
                addLegacyKeygenHeader: isKeygen,
                retry: 3
            )
        }
    }

    private static func sendWithRetry(
        httpClient: HTTPClientProtocol,
        baseURL: URL,
        sessionID: String,
        msg: Message,
        messageID: String?,
        addLegacyKeygenHeader: Bool,
        retry: Int
    ) async {
        var remaining = retry
        repeat {
            do {
                _ = try await httpClient.request(TssRelayAPI(
                    baseURL: baseURL,
                    endpoint: .sendMessage(
                        sessionID: sessionID,
                        message: msg,
                        messageID: messageID,
                        addLegacyKeygenHeader: addLegacyKeygenHeader
                    )
                ))
                logger.debug("send message (\(msg.hash) to (\(msg.to)) successfully")
                return
            } catch let HTTPError.statusCode(code, _) {
                logger.error("invalid response code: \(code)")
                return
            } catch {
                logger.error("fail to send message,error:\(error.localizedDescription)")
                if remaining == 0 {
                    return
                }
                remaining -= 1
            }
        } while remaining >= 0
    }
}
