import Cache
import CryptoKit
import Foundation
import Network
import OSLog
import Swifter
import CryptoSwift

public final class Mediator {
    private let logger = Logger(subsystem: "Mediator", category: "communication")
    let port: UInt16 = 18080
    let server = HttpServer()
    let cache = ConcurrentCache()
    private var service: NetService
    private let lock = NSLock()

    // Singleton
    public static let shared = Mediator()
    private init() {
        self.service = NetService(domain: "local.", type: "_http._tcp", name: "VultisigApp", port: Int32(self.port))
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
        // DELETE a message , client indicate it already received it
        self.server.DELETE["/message/:sessionID/:participantKey/:hash"] = self.deleteMessage
        // coordinate keysign finish
        self.server.POST["/complete/:seesionID/keysign"] = self.keysignFinish
        self.server.GET["/complete/:seesionID/keysign"] = self.keysignFinish

        // POST/GET , to notifiy all parties to start keygen/keysign
        self.server["/start/:sessionID"] = self.startKeygenOrKeysign

        // POST, mark a keygen has been complete
        self.server["/complete/:sessionID"] = self.keygenFinishSession

        // Payload
        self.server["/payload/:hash"] = self.processPayload

        // setup message
        self.server["/setup-message/:sessionID"] = self.processSetupMessage

    }

    // start the server
    public func start(name: String) {
        do {
            self.cache.removeAll() // clean up all
            self.service = NetService(domain: "local.", type: "_http._tcp", name: name, port: Int32(self.port))
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
        // clean up all
        self.cache.removeAll()
    }

    private func startKeygenOrKeysign(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "session-\(cleanSessionID)-start"
        // self.logger.debug("request session id is: \(cleanSessionID)")
        do {
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
                if !self.cache.objectExists(forKey: key) {
                    // self.logger.debug("session didn't start, can't find key:\(key)")
                    return HttpResponse.notFound
                }
                let cachedSession = try self.cache.getObject(forKey: key) as? Session
                if let cachedSession {
                    return HttpResponse.ok(.json(cachedSession.Participants))
                }
                return HttpResponse.notAcceptable
            default:
                return HttpResponse.notFound
            }
        } catch {
            logger.error("fail to process request to start keygen/keysign,error:\(error.localizedDescription)")
            return HttpResponse.internalServerError
        }
    }

    private func sendMessage(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let messageID = req.headers["message_id"] // message_id indicate the keysign message id
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(Message.self, from: Data(req.body))
            for recipient in message.to {
                var key = "\(cleanSessionID)-\(recipient)-\(message.hash)"
                if let messageID {
                    key = "\(cleanSessionID)-\(recipient)-\(messageID)-\(message.hash)"
                }
                logger.info("received message \(key) from \(message.from) to \(recipient)")
                // sometimes this might fail because the object with the same key already exist , probably because of client side retry
                // thus if the object exist already , remove it first , and then add it back
                self.cache.setObject(message, forKey: key)
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
        do {
            let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanParticipantKey = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
            let messageID = req.headers["message_id"]
            // make sure the keyprefix endwith `-` so it doesn't clash with the participant key
            var keyPrefix = "\(cleanSessionID)-\(cleanParticipantKey)-"
            if let messageID {
                keyPrefix = "\(cleanSessionID)-\(cleanParticipantKey)-\(messageID)-"
            }
            let encoder = JSONEncoder()

            // get all the messages
            let allKeys = self.cache.getAllKeys()
            let messages = try allKeys.filter {
                $0.hasPrefix(keyPrefix)
            }.compactMap { cacheKey in
                try self.cache.getObject(forKey: cacheKey) as? Message
            }
            let result = try encoder.encode(messages)
            return HttpResponse.ok(.data(result, contentType: "application/json"))
        } catch {
            self.logger.error("fail to encode object to json,error:\(error)")
            return HttpResponse.internalServerError
        }
    }

    private func postSession(req: HttpRequest) -> HttpResponse {
        return processSession(req: req, keyPrefix: nil)
    }

    private func keygenFinishSession(req: HttpRequest) -> HttpResponse {
        switch req.method {
        case "POST":
            return processSession(req: req, keyPrefix: "complete")
        case "GET":
            return processGetSession(req: req, keyPrefix: "complete")
        default:
            return HttpResponse.notAcceptable
        }
    }

    private func processSession(req: HttpRequest, keyPrefix: String?) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            self.logger.error("request session id is empty")
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        var key = ""
        if let keyPrefix {
            key = "\(keyPrefix)-session-\(cleanSessionID)"
        } else {
            key = "session-\(cleanSessionID)"
        }
        do {
            let decoder = JSONDecoder()
            let p = try decoder.decode([String].self, from: Data(req.body))
            if self.cache.objectExists(forKey: key) {
                if let cachedValue = try self.cache.getObject(forKey: key) as? Session {
                    for newParticipant in p {
                        if !cachedValue.Participants.contains(where: { $0 == newParticipant }) {
                            cachedValue.Participants.append(newParticipant)
                        }
                    }
                    self.cache.setObject(cachedValue, forKey: key)
                }
            } else {
                let session = Session(SessionID: cleanSessionID, Participants: p)
                self.cache.setObject(session, forKey: key)
            }
            self.logger.debug("session id is: \(cleanSessionID), participants:\(p) stored with key:\(key)")

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
        let key = "session-\(cleanSessionID)"
        self.cache.removeObject(key: key)
        let keyStart = "\(key)-start"
        self.cache.removeObject(key: keyStart)
        return HttpResponse.ok(.text(""))
    }

    private func getSession(req: HttpRequest) -> HttpResponse {
        return processGetSession(req: req, keyPrefix: nil)
    }

    private func processGetSession(req: HttpRequest, keyPrefix: String?) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }

        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        var key = ""
        if let keyPrefix {
            key = "\(keyPrefix)-session-\(cleanSessionID)"
        } else {
            key = "session-\(cleanSessionID)"
        }
        do {
            if let cachedValue = try self.cache.getObject(forKey: key) as? Session {
                return HttpResponse.ok(.json(cachedValue.Participants))
            }
        } catch Cache.StorageError.notFound {
            logger.error("session with key:\(key) not found")
            return HttpResponse.notFound
        } catch {
            logger.error("fail to get session,error:\(error.localizedDescription)")
        }
        return HttpResponse.notFound
    }

    private func deleteMessage(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let participantID = req.params[":participantKey"] else {
            return HttpResponse.badRequest(.text("participantKey is empty"))
        }
        let cleanParticipantKey = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let msgHash = req.params[":hash"] else {
            return HttpResponse.badRequest(.text("hash is empty"))
        }
        let messageID = req.headers["message_id"]
        var key = "\(cleanSessionID)-\(cleanParticipantKey)-\(msgHash)"
        if let messageID {
            key = "\(cleanSessionID)-\(cleanParticipantKey)-\(messageID)-\(msgHash)"
        }
        logger.info("message with key:\(key) deleted")
        self.cache.removeObject(key: key)
        return HttpResponse.ok(.text(""))
    }

    func keysignFinish(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        guard let messageID = req.headers["message_id"] else {
            return HttpResponse.badRequest(.text("message_id is empty"))
        }

        let cleanSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "keysign-\(cleanSessionID)-\(messageID)-complete"
        self.logger.debug("keysign complete, key:\(key)")
        do {
            switch req.method {
            case "POST":
                let body = String(data: Data(req.body), encoding: .utf8) ?? ""
                self.cache.setObject(body, forKey: key)
                return HttpResponse.ok(.text(""))
            case "GET":
                if !self.cache.objectExists(forKey: key) {
                    return HttpResponse.notFound
                }
                let sig = try self.cache.getObject(forKey: key) as? String
                if let sig {
                    return HttpResponse.ok(.text(sig))
                }
                return HttpResponse.notAcceptable
            default:
                return HttpResponse.notFound
            }
        } catch {
            logger.error("fail to process request to start keygen/keysign,error:\(error.localizedDescription)")
            return HttpResponse.internalServerError
        }
    }

    func processPayload(req: HttpRequest) -> HttpResponse {
        guard let hash = req.params[":hash"] else {
            return HttpResponse.badRequest(.text("hash is empty"))
        }
        do {
            switch req.method {
            case "POST":
                let body = String(data: Data(req.body), encoding: .utf8) ?? ""
                let hashBody = body.sha256()
                if hash != hashBody {
                    return HttpResponse.badRequest(.text("invalid hash"))
                }
                print("accept payload: \(hash)")
                self.cache.setObject(body, forKey: hash)
                return HttpResponse.created
            case "GET":
                if !self.cache.objectExists(forKey: hash) {
                    return HttpResponse.notFound
                }
                let body = try self.cache.getObject(forKey: hash) as? String
                if let body {
                    let bodyHash = body.sha256()
                    if bodyHash != hash {
                        return HttpResponse.badRequest(.text("invalid hash"))
                    }
                    print("return payload: \(hash)")
                    return HttpResponse.ok(.text(body))
                }
                return HttpResponse.notAcceptable
            default:
                return HttpResponse.notFound
            }
        } catch {
            logger.error("fail to process request to payload,error:\(error.localizedDescription)")
            return HttpResponse.internalServerError
        }
    }

    func processSetupMessage(req: HttpRequest) -> HttpResponse {
        guard let sessionID = req.params[":sessionID"] else {
            return HttpResponse.badRequest(.text("sessionID is empty"))
        }
        var key = "setup-\(sessionID)"
        let messageID = req.headers["message_id"] ?? req.headers["message-id"]
        if let messageID, !messageID.isEmpty {
            key += "-\(messageID)"
        }
        do {
            switch req.method {
            case "POST":
                let body = String(data: Data(req.body), encoding: .utf8) ?? ""
                self.cache.setObject(body, forKey: key)
                return HttpResponse.created
            case "GET":
                if !self.cache.objectExists(forKey: key) {
                    return HttpResponse.notFound
                }
                let body = try self.cache.getObject(forKey: key) as? String
                if let body {
                    return HttpResponse.ok(.text(body))
                }
                return HttpResponse.notAcceptable
            default:
                return HttpResponse.notFound
            }
        } catch {
            logger.error("fail to process request to payload,error:\(error.localizedDescription)")
            return HttpResponse.internalServerError
        }
    }

    deinit {
        self.cache.removeAll() // clean up cache
    }
}
