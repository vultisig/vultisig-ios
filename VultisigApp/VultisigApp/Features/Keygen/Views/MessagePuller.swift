//
//  MessagePuller.swift
//  VultisigApp
//

import Foundation
import Mediator
import OSLog
import Tss

class MessagePuller: ObservableObject {
    let encryptionKeyHex: String
    let vaultPubKey: String
    var cache = NSCache<NSString, AnyObject>()
    private var pollingInboundMessages = true
    private let logger = Logger(subsystem: "com.vultisig.app", category: "net-message-puller")
    private var currentTask: Task<Void, Error>? = nil
    let encryptGCM: Bool
    private let httpClient: HTTPClientProtocol

    init(encryptionKeyHex: String,
         pubKey: String,
         encryptGCM: Bool,
         httpClient: HTTPClientProtocol = HTTPClient()) {
        self.encryptionKeyHex = encryptionKeyHex
        self.vaultPubKey = pubKey
        self.encryptGCM = encryptGCM
        self.httpClient = httpClient
    }

    func stop() {
        pollingInboundMessages = false
        cache.removeAllObjects()
        currentTask?.cancel()
    }

    func pollMessages(mediatorURL: String,
                      sessionID: String,
                      localPartyKey: String,
                      tssService: TssServiceImpl,
                      messageID: String?) {
        pollingInboundMessages = true
        currentTask = Task.detached {
            repeat {
                if Task.isCancelled {
                    self.logger.debug("stop pulling for messageid:\(messageID ?? "")")
                    return
                }
                self.logger.debug("pulling for messageid:\(messageID ?? "")")
                await self.pollInboundMessages(mediatorURL: mediatorURL,
                                               sessionID: sessionID,
                                               localPartyKey: localPartyKey,
                                               tssService: tssService,
                                               messageID: messageID)
                try await Task.sleep(for: .seconds(1)) // Back off 1s
            } while self.pollingInboundMessages
        }
    }

    private func pollInboundMessages(mediatorURL: String,
                                     sessionID: String,
                                     localPartyKey: String,
                                     tssService: TssServiceImpl,
                                     messageID: String?) async {
        guard let baseURL = URL(string: mediatorURL) else {
            logger.error("Invalid mediator URL: \(mediatorURL)")
            return
        }

        let response: HTTPResponse<Data>
        do {
            response = try await httpClient.request(TssRelayAPI(
                baseURL: baseURL,
                endpoint: .pollInboundMessages(
                    sessionID: sessionID,
                    localPartyID: localPartyKey,
                    messageID: messageID
                )
            ))
        } catch HTTPError.statusCode(404, _) {
            // session warming up — silent, matches the original 404 short-circuit
            return
        } catch {
            logger.error("fail to get inbound message,error:\(error.localizedDescription)")
            return
        }

        do {
            let msgs = try JSONDecoder().decode([Message].self, from: response.data)
            let sortedMsgs = msgs.sorted(by: { $0.sequence_no < $1.sequence_no })
            for msg in sortedMsgs {
                var key = "\(sessionID)-\(localPartyKey)-\(msg.hash)" as NSString
                if let messageID {
                    key = "\(sessionID)-\(localPartyKey)-\(messageID)-\(msg.hash)" as NSString
                }
                if cache.object(forKey: key) != nil {
                    logger.info("message with key:\(key) has been applied before")
                    continue
                }
                logger.debug("Got message from: \(msg.from), to: \(msg.to), key:\(key)")
                let decryptedBody: String?
                if encryptGCM {
                    decryptedBody = msg.body.aesDecryptGCM(key: encryptionKeyHex)
                } else {
                    decryptedBody = msg.body.aesDecrypt(key: encryptionKeyHex)
                }
                try tssService.applyData(decryptedBody)
                cache.setObject(NSObject(), forKey: key)
                Task {
                    // delete from a separate task — we don't care about the result
                    await deleteMessageFromServer(baseURL: baseURL,
                                                  sessionID: sessionID,
                                                  localPartyKey: localPartyKey,
                                                  hash: msg.hash,
                                                  messageID: messageID)
                }
            }
        } catch {
            logger.error("Failed to decode response to JSON, data: \(response.data), error: \(error.localizedDescription)")
        }
    }

    private func deleteMessageFromServer(
        baseURL: URL,
        sessionID: String,
        localPartyKey: String,
        hash: String,
        messageID: String?
    ) async {
        do {
            _ = try await httpClient.request(TssRelayAPI(
                baseURL: baseURL,
                endpoint: .deleteMessage(
                    sessionID: sessionID,
                    localPartyID: localPartyKey,
                    hash: hash,
                    messageID: messageID
                )
            ))
        } catch {
            logger.error("Failed to delete message from server, error: \(error.localizedDescription)")
        }
    }
}
