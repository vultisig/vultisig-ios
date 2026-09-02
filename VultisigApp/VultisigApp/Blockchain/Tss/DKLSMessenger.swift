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

private let logger = Log.tss.network
final class DKLSMessenger {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    let mediatorURL: String
    let sessionID: String
    var messageID: String?
    let encryptionKeyHex: String
    var counter: Int64 = 1
    private let httpClient: HTTPClientProtocol
    private let sleep: Sleeper

    init(mediatorUrl: String,
         sessionID: String,
         messageID: String?,
         encryptionKeyHex: String,
         httpClient: HTTPClientProtocol = HTTPClient(),
         sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.mediatorURL = mediatorUrl
        self.sessionID = sessionID
        self.messageID = messageID
        self.encryptionKeyHex = encryptionKeyHex
        self.httpClient = httpClient
        self.sleep = sleep
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
            throw RelaySendError.invalidMessage("from is nil")
        }
        guard let to else {
            throw RelaySendError.invalidMessage("to is nil")
        }
        guard let body else {
            throw RelaySendError.invalidMessage("body is nil")
        }
        guard let baseURL = URL(string: mediatorURL) else {
            throw RelaySendError.invalidMessage("invalid mediator URL: \(mediatorURL)")
        }
        guard let encryptedBody = body.aesEncryptGCM(key: self.encryptionKeyHex) else {
            throw RelaySendError.invalidMessage("fail to encrypt message body")
        }
        // Built once: every retry must carry the same hash and sequence number
        // so the relay and the receiver dedupe it instead of applying it twice.
        let msg = Message(session_id: sessionID,
                          from: fromParty,
                          to: [to],
                          body: encryptedBody,
                          hash: Utils.getMessageBodyHash(msg: body),
                          sequenceNo: self.counter)
        self.counter += 1
        let target = TssRelayAPI(
            baseURL: baseURL,
            endpoint: .sendMessage(
                sessionID: sessionID,
                message: msg,
                messageID: messageID,
                addLegacyKeygenHeader: false
            )
        )

        var attempt = 1
        while true {
            do {
                _ = try await httpClient.request(target)
                logger.info("send message (\(msg.hash) to (\(msg.to)) successfully, sequenceNo:\(msg.sequence_no)")
                return
            } catch {
                guard RelaySendRetryPolicy.isRetryable(error) else {
                    if case HTTPError.statusCode(let code, _) = error {
                        throw RelaySendError.rejected(status: code)
                    }
                    throw error
                }
                guard attempt < RelaySendRetryPolicy.maxAttempts else {
                    throw RelaySendError.exhausted(attempts: attempt, lastError: error)
                }
                logger.warning("fail to send message \(msg.hash), attempt \(attempt)/\(RelaySendRetryPolicy.maxAttempts): \(error.localizedDescription)")
                try await sleep(RelaySendRetryPolicy.backoff(afterAttempt: attempt))
                attempt += 1
            }
        }
    }
}
