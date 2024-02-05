import CryptoKit
import Foundation
import Network
import OSLog
import Swifter

public final class Mediator {
    private let logger = Logger(subsystem: "Mediator", category: "communication")
    let port: UInt16 = 8080
    let server = HttpServer()
    let cache = NSCache<NSString, AnyObject>()
    private let service: NetService
    
    // Singleton
    public static let shared = Mediator()
    private init() {
        self.cache.name = "localcache"
        self.cache.countLimit = 1024
        self.service = NetService(domain: "local.", type: "_http._tcp", name: "VoltixApp", port: Int32(self.port))
        self.setupRoute()
    }
    
    private func setupRoute() {
        // POST with a sessionID
        self.server.POST["/:sessionID"] = self.postSession
        // DELETE all messages related to the sessionID
        self.server.DELETE["/:sessionID"] = self.deleteSession
        // GET all participants that are linked to a specific session
        self.server.GET["/:sessionID"] = self.getSession
        // POST a message to a specific session
        self.server.POST["/message/:sessionID"] = self.sendMessage
        // GET all messages for a specific session and participant
        self.server.GET["/message/:sessionID/:participantKey"] = self.getMessages
        self.server.GET["/message/:sessionID/:participantKey/all"] = self.getAllMessages
        // POST/GET , to notifiy all parties to start keygen/keysign
        self.server["/start/:sessionID"] = self.startKeygenOrKeysign
    }
    
    // start the server
    public func start() {
        do {
            try self.server.start(self.port)
            self.service.publish()
        } catch {
            self.logger.error("fail to start http server on port: \(self.port), error:\(error)")
            return
        }
        self.logger.info("server started successfully")
    }
    
    // stop mediator server
    public func stop() {
        self.server.stop()
        self.cache.removeAllObjects()
    }
    
    private func startKeygenOrKeysign(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "session-\(cleanSessionID)-start" as NSString
        self.logger.debug("request session id is: \(cleanSessionID)")
        switch req.method {
        case "POST":
            do {
                let decoder = JSONDecoder()
                let p = try decoder.decode([String].self, from: Data(req.body))
                self.cache.setObject(Session(SessionID: cleanSessionID, Participants: p), forKey: key)
            } catch {
                self.logger.error("fail to start keygen/keysign,error:\(error.localizedDescription)")
                return HttpResponse.badRequest(.none)
            }
            
            return HttpResponse.ok(.text(""))
        case "GET":
            guard let cachedSession = self.cache.object(forKey: key) as? Session else {
                self.logger.debug("session didn't start, can't find key:\(key)")
                return HttpResponse.notFound
            }
            return HttpResponse.ok(.json(cachedSession.Participants))
          
        default:
            return HttpResponse.notAcceptable
        }
    }
    
    private func sendMessage(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(Message.self, from: Data(req.body))
            for recipient in message.to {
                let key = "\(cleanSessionID)-\(recipient)" as NSString
                if let cachedMessages = self.cache.object(forKey: key) as? cacheItem {
                    cachedMessages.messages.append(message)
                    self.cache.setObject(cachedMessages, forKey: key)
                } else {
                    let newCacheItem = cacheItem(messages: [message])
                    self.cache.setObject(newCacheItem, forKey: key)
                }
            }
        } catch {
            self.logger.error("fail to decode message payload,error:\(error)")
            return HttpResponse.badRequest(.text("fail to decode payload"))
        }
        return HttpResponse.accepted
    }
    
    private func getMessages(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        guard let participantID = req.params[":participantKey"] else {
            return HttpResponse.badRequest(.text("participantKey is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanParticipantKey = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(cleanSessionID)-\(cleanParticipantKey)" as NSString
        guard let cachedValue = self.cache.object(forKey: key) as? cacheItem else {
            return HttpResponse.notFound
        }
        let encoder = JSONEncoder()
        do {
            var messages = [Message]()
            for m in cachedValue.messages {
                let cacheKey = "\(cleanSessionID)-\(cleanParticipantKey)-\(m.hash)" as NSString
                self.logger.debug("cache key: \(cacheKey)")
                if self.cache.object(forKey: cacheKey) is NSString {
                    // message has been passed to client already
                    self.logger.debug("\(cacheKey) message has been passed to client, ignore")
                    continue
                }
                self.cache.setObject(cacheKey, forKey: cacheKey)
                messages.append(m)
            }
            
            let result = try encoder.encode(messages)
            return HttpResponse.ok(.data(result, contentType: "application/json"))
        } catch {
            self.logger.error("fail to encode object to json,error:\(error)")
            return HttpResponse.internalServerError
        }
    }

    private func getAllMessages(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        guard let participantID = req.params[":participantKey"] else {
            return HttpResponse.badRequest(.text("participantKey is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanParticipantKey = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(cleanSessionID)-\(cleanParticipantKey)" as NSString
        guard let cachedValue = self.cache.object(forKey: key) as? cacheItem else {
            return HttpResponse.notFound
        }
        let encoder = JSONEncoder()
        do {
            let result = try encoder.encode(cachedValue.messages)
            return HttpResponse.ok(.data(result, contentType: "application/json"))
        } catch {
            self.logger.error("fail to encode object to json,error:\(error)")
            return HttpResponse.internalServerError
        }
    }
    
    private func postSession(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            self.logger.error("request session id is empty")
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "session-\(cleanSessionID)" as NSString
        self.logger.debug("request session id is: \(cleanSessionID)")
        do {
            let decoder = JSONDecoder()
            let p = try decoder.decode([String].self, from: Data(req.body))
            if let cachedValue = self.cache.object(forKey: key) as? Session {
                for newParticipant in p {
                    if !cachedValue.Participants.contains(where: { $0 == newParticipant }) {
                        cachedValue.Participants.append(newParticipant)
                    }
                }
                self.cache.setObject(cachedValue, forKey: key)
            } else {
                let session = Session(SessionID: cleanSessionID, Participants: p)
                self.cache.setObject(session, forKey: key)
            }
        } catch {
            self.logger.error("fail to decode json body,error:\(error)")
            return HttpResponse.badRequest(.text("invalid json payload"))
        }
        return HttpResponse.created
    }
    
    private func deleteSession(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "session-\(cleanSessionID)" as NSString
        self.cache.removeObject(forKey: key)
        let keyStart = NSString(string: "\(key)-start")
        self.cache.removeObject(forKey: keyStart)
        return HttpResponse.ok(.text(""))
    }
    
    private func getSession(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "session-\(cleanSessionID)" as NSString
        
        if let cachedValue = self.cache.object(forKey: key) as? Session {
            self.logger.debug("session obj : \(cachedValue.SessionID), participants: \(cachedValue.Participants)")
            return HttpResponse.ok(.json(cachedValue.Participants))
        } else {
            self.logger.error("cached object not found")
            return HttpResponse.notFound
        }
    }
    
    private func MD5(string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
    }

    deinit {
        self.cache.removeAllObjects() // clean up cache
    }
}
