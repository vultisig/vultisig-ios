//
//  PeerDiscoveryViewModel.swift
//  VoltixApp
//

import Foundation
import Mediator
import OSLog

class CommunicationViewModel: ObservableObject {
    private let logger = Logger(subsystem: "client", category: "websocket")
    @Published var participants = [String]()
    private var connection: URLSessionWebSocketTask?
    private var working = true

    init() {}

    let serverAddr = "ws://127.0.0.1:8080/websocket/ws"

    func connect(localKey: String) -> URLSessionWebSocketTask {
        let url = URL(string: serverAddr)!
        let connection = URLSession.shared.webSocketTask(with: url)
        connection.resume()
        connection.send(.string(getHelloMessage(localKey: localKey))) { err in
            if let err {
                self.logger.error("fail to send hello message,error:\(err.localizedDescription))")
            }
        }
        return connection
    }

    func getHelloMessage(localKey: String) -> String {
        let hello = HelloMessage(clientKey: localKey)
        let encoder = JSONEncoder()
        do {
            let msg = try encoder.encode(hello)
            let socketMsg = WebsocketMessage(header: .HelloMessage, body: String(data: msg, encoding: .utf8)!)
            let finalMsg = try encoder.encode(socketMsg)
            return String(data: finalMsg, encoding: .utf8)!
        } catch {
            logger.error("fail to create hello message")
        }
        return ""
    }

    func startSession(sessionID: String, localKey: String) {
        guard let sessionMsg = getSessionMessage(sessionID: sessionID, localKey: localKey) else {
            return
        }

        guard let finalMsg = getSocketMessage(header: .StartSession, body: sessionMsg) else {
            logger.error("fail to get socket message when start session")
            return
        }
        connection?.send(.string(finalMsg), completionHandler: { err in
            if let err {
                self.logger.error("fail to start session")
            }
        })
    }

    func getSessionMessage(sessionID: String, localKey: String) -> String? {
        let startSessionMsg = SessionMessage(clientKey: localKey, sessionID: sessionID)
        let encoder = JSONEncoder()
        do {
            let msg = try encoder.encode(startSessionMsg)
            return String(data: msg, encoding: .utf8)
        } catch {
            logger.error("fail to create hello message")
        }
        return nil
    }

    func getSocketMessage(header: MessageHeader, body: String) -> String? {
        let encoder = JSONEncoder()
        do {
            let socketMsg = WebsocketMessage(header: header, body: body)
            let finalMsgData = try encoder.encode(socketMsg)
            return String(data: finalMsgData, encoding: .utf8)
        } catch {
            logger.error("fail to generate socket message")
        }
        return nil
    }

    func endSession(sessionID: String, localKey: String) {
        guard let sessionMsg = getSessionMessage(sessionID: sessionID, localKey: localKey) else {
            return
        }

        guard let socketMsg = getSocketMessage(header: .EndSession, body: sessionMsg) else {
            logger.error("fail to get socket message when end session")
            return
        }

        connection?.send(.string(socketMsg), completionHandler: { err in
            if let err {
                self.logger.error("fail to start session")
            }
        })
    }

    func StartEventLoop(localKey: String) {
        connection = connect(localKey: localKey)
        guard connection != nil else {
            return
        }

        Task {
            repeat {
                do {
                    connection?.receive(completionHandler: { result in
                        switch result {
                        case .success(let message):
                            switch message {
                            case .string(let text):
                                self.logger.info("receive message:\(text)")
                                self.processMessage(message: text)
                            case .data(let data):
                                self.logger.info("receive data:\(data)")
                            @unknown default:
                                self.logger.error("unknown message")
                            }
                        case .failure(let error):
                            self.logger.error("fail to receive message:\(error.localizedDescription)")
                        }
                    })
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    logger.error("fail to receive message:\(error.localizedDescription)")
                }
            } while working
        }
    }

    func processMessage(message: String) {
        let decoder = JSONDecoder()
        guard let contentData = message.data(using: .utf8) else {
            logger.error("content: \(message) can't be decoded correctly")
            return
        }
        do {
            let socketMsg = try decoder.decode(WebsocketMessage.self, from: contentData)
            switch socketMsg.header {
            case .HelloMessage:
                logger.error("client get hello message , shouldn't happen")
            case .DropSession:
                logger.error("client get drop session message")
            case .EndSession:
                logger.error("client get start session message , shouldn't happen")
            case .JoinSession:
                logger.error("client get join session message")
            case .StartSession:
                logger.error("client get start session message , shouldn't happen")
            case .StartTSS:
                logger.error("client get start TSS message , kick off keygen or keysign")
            case .TSSRouting:
                logger.error("client get TSS Routing message")
            }
        } catch {
            logger.error("fail to process message,error:\(error.localizedDescription)")
        }
    }
}
