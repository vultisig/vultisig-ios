// The Swift Programming Language
// https://docs.swift.org/swift-book

import Swifter
import Network
import Foundation
import OSLog

public class Mediator {
    private let logger = Logger(subsystem: "Mediator", category: "communication")
    let port: UInt16
    let server = HttpServer()
    let cache = NSCache<NSString,AnyObject>()
    
    public init(serverPort: UInt16){
        self.port = serverPort
        self.cache.name = "localcache"
        cache.countLimit = 1024
        setupRoute()
    }
    
    func setupRoute(){
        // POST with a sessionID
        self.server.POST["/:sessionID"] = self.postSession
        // DELETE all messages related to the sessionID
        self.server.DELETE["/:sessionID"] = self.deleteSession
        // GET all participants that are linked to a specific session
        self.server.GET["/:sessionID"] = self.getSession
        self.server.POST["/message/:sessionID"] = self.sendMessage
        self.server.GET["/message/:sessionID/:participantKey"] = self.getMessages
    }
    
    // start the server
    public func start() {
        do{
            logger.log("\(self.server.routes)")
            try self.server.start(self.port)
        }
        catch{
            logger.error("fail to start http server on port: \(self.port), error:\(error)")
            return
        }
        logger.info("server started successfully")
        // publish through bonjour
    }
    
    func sendMessage(req: HttpRequest) -> HttpResponse {
        return HttpResponse.accepted
    }
    
    func getMessages(req: HttpRequest) -> HttpResponse {
        return HttpResponse.ok(.json(""))
    }
    func postSession(req: HttpRequest) -> HttpResponse{
        let sessionID = req.params[":sessionID"]
        if let sessionID {
            let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "session-\(cleanSessionID)" as NSString
            logger.debug("request session id is: \(cleanSessionID)")
            
            var p: [String]
            do {
                let decoder = JSONDecoder()
                p = try decoder.decode([String].self, from: Data(req.body))
            } catch {
                logger.error("fail to decode json body,error:\(error)")
                return HttpResponse.badRequest(.text("invalid json payload"))
            }
            let session = Session(SessionID: cleanSessionID, Participants: p)
            if let cachedValue = self.cache.object(forKey: key){
                let r = cachedValue as? Session
                if let r {
                    r.Participants.append(contentsOf: p)
                    self.cache.setObject(r, forKey: key)
                }else{
                    self.cache.setObject(session, forKey: key)
                }
                
            } else {
                self.cache.setObject(session, forKey: key)
            }
        } else {
            logger.error("request session id is empty")
            return HttpResponse.badRequest(nil)
        }
        
        return HttpResponse.created
    }
    
    func deleteSession(req: HttpRequest) -> HttpResponse {
        let sessionID = req.params[":sessionID"]
        if let sessionID {
            let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "session-\(cleanSessionID)" as NSString
            self.cache.removeObject(forKey: key)
        }
        // return a status code ok , with empty body
        return HttpResponse.ok(HttpResponseBody.text(""))
    }
    
    func getSession(req:HttpRequest) -> HttpResponse{
        let sessionID = req.params[":sessionID"]
        if let sessionID {
            let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "session-\(cleanSessionID)" as NSString
            if let cachedValue = self.cache.object(forKey: key){
                let sessionObj = cachedValue as? Session
                if let sessionObj {
                    logger.info("session obj : \(sessionObj.SessionID), participants: \(sessionObj.Participants)")
                    return HttpResponse.ok(.json(sessionObj.Participants))
                }
            }
        }
        return HttpResponse.notFound
    }
    
    deinit{
        self.cache.removeAllObjects() // clean up cache
    }
    
}
