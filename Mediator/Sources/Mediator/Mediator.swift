import Swifter
import Network
import Foundation
import OSLog

public final class Mediator {
    private let logger = Logger(subsystem: "Mediator", category: "communication")
    let port: UInt16 = 8080
    let server = HttpServer()
    let cache = NSCache<NSString,AnyObject>()
    
    // Singleton
    static public let shared = Mediator()
    private init() {
        self.cache.name = "localcache"
        cache.countLimit = 1024
        setupRoute()
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
    }
    
    // start the server
    public func start() {
        do {
            try self.server.start(self.port)
            let service = NetService(domain: "local.", type: "_http._tcp", name: "VoltixApp",port: Int32(self.port))
            service.publish()
        }
        catch{
            logger.error("fail to start http server on port: \(self.port), error:\(error)")
            return
        }
        logger.info("server started successfully")
        
    }
    
    // stop mediator server
    public func stop() {
        self.server.stop()
        self.cache.removeAllObjects()
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
            logger.error("fail to decode message payload,error:\(error)")
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
            logger.error("cached object can't be retrieved")
            return HttpResponse.notFound
        }
        let encoder = JSONEncoder()
        do {
            let result = try encoder.encode(cachedValue.messages)
            return HttpResponse.ok(.data(result, contentType: "application/json"))
        } catch {
            logger.error("fail to encode object to json,error:\(error)")
            return HttpResponse.internalServerError
        }
    }
    
    private func postSession(req: HttpRequest) -> HttpResponse{
        guard let sessionID = req.params[":sessionID"] else {
            logger.error("request session id is empty")
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "session-\(cleanSessionID)" as NSString
        logger.debug("request session id is: \(cleanSessionID)")
        do {
            let decoder = JSONDecoder()
            let p = try decoder.decode([String].self, from: Data(req.body))
            
            if let cachedValue = self.cache.object(forKey: key) as? Session{
                cachedValue.Participants.append(contentsOf: p)
                self.cache.setObject(cachedValue, forKey: key)
            } else {
                let session = Session(SessionID: cleanSessionID, Participants: p)
                self.cache.setObject(session, forKey: key)
            }
        } catch {
            logger.error("fail to decode json body,error:\(error)")
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
        return HttpResponse.ok(.text(""))
    }
    
    private func getSession(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "session-\(cleanSessionID)" as NSString
        
        if let cachedValue = self.cache.object(forKey: key) as? Session {
            logger.info("session obj : \(cachedValue.SessionID), participants: \(cachedValue.Participants)")
            return HttpResponse.ok(.json(cachedValue.Participants))
        } else {
            logger.error("cached object not found")
            return HttpResponse.notFound
        }
    }
    
    deinit {
        self.cache.removeAllObjects() // clean up cache
    }
}
