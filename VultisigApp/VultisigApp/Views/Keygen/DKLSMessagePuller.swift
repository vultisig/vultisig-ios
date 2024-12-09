//
//  DKLSMessagePuller.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/12/2024.
//


import Foundation
import Mediator
import OSLog
import godkls

class DKLSMessagePuller: ObservableObject {
    let encryptionKeyHex: String
    var cache = NSCache<NSString, AnyObject>()
    private var pollingInboundMessages = true
    private let logger = Logger(subsystem: "dkls-message-puller", category: "communication")
    private var currentTask: Task<Void,Error>? = nil
    
    init(encryptionKeyHex:String){
        self.encryptionKeyHex = encryptionKeyHex
    }
    
    func stop() {
        pollingInboundMessages = false
        cache.removeAllObjects()
        currentTask?.cancel()
    }
    
    func pollMessages(mediatorURL: String,
                      sessionID: String,
                      localPartyKey: String,
                      handler: godkls.Handle,
                      messageID: String?)
    {
        pollingInboundMessages = true
        currentTask = Task.detached {
            repeat {
                if Task.isCancelled {
                    print("stop pulling for messageid:\(messageID ?? "")")
                    return
                }
                print("pulling for messageid:\(messageID ?? "")")
                self.pollInboundMessages(mediatorURL: mediatorURL,
                                         sessionID: sessionID,
                                         localPartyKey: localPartyKey,
                                         handler: handler,
                                         messageID: messageID)
                try await Task.sleep(for: .seconds(1)) // Back off 1s
            } while self.pollingInboundMessages
        }
    }
    
    func getHeaders(messageID: String?) -> [String:String]{
        var header = [String: String]()
        if let messageID {
            header["message_id"] = messageID
        } else {
            header = TssHelper.getKeygenRequestHeader()
        }
        return header
    }
    private func pollInboundMessages(mediatorURL: String,
                                     sessionID: String,
                                     localPartyKey: String,
                                     handler: godkls.Handle,
                                     messageID: String?) {
        let urlString = "\(mediatorURL)/message/\(sessionID)/\(localPartyKey)"
        Utils.getRequest(urlString: urlString, headers: getHeaders(messageID: messageID), completion: { result in
            switch result {
            case .success(let data):
                do {
                    print("Response: \(String(data:data,encoding: .utf8) ?? "")")
                    let decoder = JSONDecoder()
                    let msgs = try decoder.decode([Message].self, from: data)
                    let sortedMsgs = msgs.sorted(by: { $0.sequence_no < $1.sequence_no })
                    for msg in sortedMsgs {
                        var key = "\(sessionID)-\(localPartyKey)-\(msg.hash)" as NSString
                        if let messageID {
                            key = "\(sessionID)-\(localPartyKey)-\(messageID)-\(msg.hash)" as NSString
                        }
                        if self.cache.object(forKey: key) != nil {
                            self.logger.info("message with key:\(key) has been applied before")
                            // message has been applied before
                            continue
                        }
                        self.logger.debug("Got message from: \(msg.from), to: \(msg.to), key:\(key)")
                        guard let decryptedBody = msg.body.aesDecryptGCM(key: self.encryptionKeyHex) else {
                            throw DKLSError.runtimeError("fail to decrypted message body")
                        }
                        guard var decryptedBodySlice = decryptedBody.to_dkls_goslice() else {
                            throw DKLSError.runtimeError("fail to convert decrypted message to go_slice")
                        }
                        var isFinished:UInt32 = 0
                        let result = dkls_keygen_session_input_message(handler, &decryptedBodySlice, &isFinished)
                        if result != LIB_OK {
                            throw DKLSError.runtimeError("fail to apply message to dkls")
                        }
                        if isFinished != 0 {
                            // done
                        }
                        self.cache.setObject(NSObject(), forKey: key)
                        Task {
                            // delete it from a task, since we don't really care about the result
                            self.deleteMessageFromServer(mediatorURL: mediatorURL,
                                                         sessionID: sessionID,
                                                         localPartyKey: localPartyKey,
                                                         hash: msg.hash,
                                                         headers: self.getHeaders(messageID: messageID))
                        }
                    }
                } catch {
                    self.logger.error("Failed to decode response to JSON, data: \(data), error: \(error)")
                }
            case .failure(let error):
                let err = error as NSError
                if err.code != 404 {
                    self.logger.error("fail to get inbound message,error:\(error.localizedDescription)")
                }
            }
        })
    }
    
    private func deleteMessageFromServer(
        mediatorURL: String,
        sessionID: String,
        localPartyKey: String,
        hash: String,
        headers: [String:String]
    ) {
        let urlString = "\(mediatorURL)/message/\(sessionID)/\(localPartyKey)/\(hash)"
        Utils.deleteFromServer(urlString: urlString,headers: headers)
    }
}
