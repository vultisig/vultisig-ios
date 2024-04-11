//
//  MessagePuller.swift
//  VoltixApp
//

import Foundation
import Mediator
import OSLog
import Tss

class MessagePuller: ObservableObject {
    let encryptionKey: String
    var cache = NSCache<NSString, AnyObject>()
    private var pollingInboundMessages = true
    private let logger = Logger(subsystem: "message-puller", category: "communication")
    private var currentTask: Task<Void,Error>? = nil
    
    init(encryptionKey:String){
        self.encryptionKey = encryptionKey
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
                self.pollInboundMessages(mediatorURL: mediatorURL, sessionID: sessionID, localPartyKey: localPartyKey, tssService: tssService, messageID: messageID)
                try await Task.sleep(for: .seconds(1)) // Back off 1s
            } while self.pollingInboundMessages
        }
    }
    
    private func pollInboundMessages(mediatorURL: String, sessionID: String, localPartyKey: String, tssService: TssServiceImpl, messageID: String?) {
        let urlString = "\(mediatorURL)/message/\(sessionID)/\(localPartyKey)"
        var header = [String: String]()
        if let messageID {
            header["message_id"] = messageID
        }
        Utils.getRequest(urlString: urlString, headers: header, completion: { result in
            switch result {
            case .success(let data):
                do {
                    let decoder = JSONDecoder()
                    let msgs = try decoder.decode([Message].self, from: data)
                    for msg in msgs.sorted(by: { $0.sequenceNo < $1.sequenceNo }) {
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
                        let decryptedBody = msg.body.aesDecrypt(key: self.encryptionKey)
                        try tssService.applyData(decryptedBody)
                        self.cache.setObject(NSObject(), forKey: key)
                        Task {
                            // delete it from a task, since we don't really care about the result
                            self.deleteMessageFromServer(mediatorURL: mediatorURL, sessionID: sessionID, localPartyKey: localPartyKey, hash: msg.hash, messageID: messageID)
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
    
    private func deleteMessageFromServer(mediatorURL: String, sessionID: String, localPartyKey: String, hash: String, messageID: String?) {
        let urlString = "\(mediatorURL)/message/\(sessionID)/\(localPartyKey)/\(hash)"
        Utils.deleteFromServer(urlString: urlString, messageID: messageID)
    }
}
