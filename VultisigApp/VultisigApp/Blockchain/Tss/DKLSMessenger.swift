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

private let logger = Logger(subsystem: "com.vultisig.app", category: "net-dkls-messenger")
final class DKLSMessenger {
    let mediatorURL: String
    let sessionID: String
    var messageID: String?
    let encryptionKeyHex: String
    var counter: Int64 = 1
    private let httpClient: HTTPClientProtocol

    init(mediatorUrl: String,
         sessionID: String,
         messageID: String?,
         encryptionKeyHex: String,
         httpClient: HTTPClientProtocol = HTTPClient()) {
        self.mediatorURL = mediatorUrl
        self.sessionID = sessionID
        self.messageID = messageID
        self.encryptionKeyHex = encryptionKeyHex
        self.httpClient = httpClient
    }

    /// Uploads a setup message to the relay server.
    /// `self.messageID` is applied first; when `additionalHeader` is provided it overrides the header
    /// so callers can route a setup message into a different namespace than the TSS exchange.
    func uploadSetupMessage(message: String, _ additionalHeader: String?) async throws {
        guard let baseURL = URL(string: mediatorURL) else {
            throw HelperError.runtimeError("invalid mediator URL: \(mediatorURL)")
        }

        guard let encryptedBody = message.aesEncryptGCM(key: self.encryptionKeyHex),
              let bodyData = encryptedBody.data(using: .utf8) else {
            throw HelperError.runtimeError("fail to encrypt message body")
        }

        do {
            _ = try await httpClient.request(TssRelayAPI(
                baseURL: baseURL,
                endpoint: .uploadSetupMessage(
                    sessionID: sessionID,
                    body: bodyData,
                    messageID: messageID,
                    additionalHeader: additionalHeader
                )
            ))
        } catch let HTTPError.statusCode(code, _) {
            throw HelperError.runtimeError("fail to setup message to relay server,status:\(code)")
        }
    }

    func downloadSetupMessageWithRetry(_ additionalHeader: String?) async throws -> String {
        var attempt = 0
        repeat {
            do {
                return try await downloadSetupMessage(additionalHeader)
            } catch {
                logger.error("fail to download setup message, error \(error.localizedDescription), attempt: \(attempt)")
                // backoff 1s
                try await Task.sleep(for: .seconds(1))
            }
            attempt = attempt + 1
        } while attempt < 10

        throw HelperError.runtimeError("fail to download setup message after 10 retries")
    }

    /// Downloads a setup message from the relay server.
    /// `self.messageID` is applied first; when `additionalHeader` is provided it overrides the header
    /// so callers can route a setup message into a different namespace than the TSS exchange.
    func downloadSetupMessage(_ additionalHeader: String?) async throws -> String {
        guard let baseURL = URL(string: mediatorURL) else {
            throw HelperError.runtimeError("invalid mediator URL: \(mediatorURL)")
        }

        let response: HTTPResponse<Data>
        do {
            response = try await httpClient.request(TssRelayAPI(
                baseURL: baseURL,
                endpoint: .downloadSetupMessage(
                    sessionID: sessionID,
                    messageID: messageID,
                    additionalHeader: additionalHeader
                )
            ))
        } catch let HTTPError.statusCode(code, _) {
            throw HelperError.runtimeError("fail to download setup message from relay server,status:\(code)")
        }

        guard let setupMsg = String(data: response.data, encoding: .utf8) else {
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
        guard let baseURL = URL(string: mediatorURL) else {
            logger.error("invalid mediator URL: \(self.mediatorURL)")
            return
        }

        guard let encryptedBody = body.aesEncryptGCM(key: self.encryptionKeyHex) else {
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

        for _ in 0...3 {
            do {
                _ = try await httpClient.request(TssRelayAPI(
                    baseURL: baseURL,
                    endpoint: .sendMessage(
                        sessionID: sessionID,
                        message: msg,
                        messageID: messageID,
                        addLegacyKeygenHeader: false
                    )
                ))
                logger.info("send message (\(msg.hash) to (\(msg.to)) successfully, sequenceNo:\(msg.sequence_no)")
                return
            } catch let HTTPError.statusCode(code, _) {
                logger.error("fail to send message to relay server,status:\(code)")
                continue
            } catch {
                logger.error("fail to send message,error:\(error.localizedDescription)")
            }
        }
    }
}
