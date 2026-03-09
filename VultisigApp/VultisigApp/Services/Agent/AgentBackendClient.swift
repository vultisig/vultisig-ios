//
//  AgentBackendClient.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import OSLog

final class AgentBackendClient {

    private let logger = Logger(subsystem: "com.vultisig", category: "AgentBackendClient")
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    // MARK: - Shared formatters (allocated once, reused on every call)

    static let sharedEncoder = JSONEncoder()
    static let sharedDecoder = JSONDecoder()

    /// Primary ISO-8601 formatter — matches timestamps WITH fractional seconds (e.g. 2026-03-06T12:34:56.789Z)
    static let sharedISO8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback — matches timestamps WITHOUT fractional seconds (e.g. 2026-03-06T12:34:56Z)
    /// Bug 5 fix: the backend sometimes omits fractional seconds; without a fallback those
    /// dates silently became Date() and scrambled message ordering in loaded chats.
    private static let sharedISO8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse an ISO-8601 string, trying fractional-second format first then falling back.
    static func parseISO8601(_ string: String) -> Date? {
        sharedISO8601.date(from: string) ?? sharedISO8601NoFrac.date(from: string)
    }

    /// Builds a fresh URLSession for each SSE stream.
    /// We use ephemeral configuration so there is NO shared connection pool:
    /// HTTP/2 ignores the `Connection: close` header and reuses TCP streams,
    /// causing -1017 "Connection reset by peer" when the server closes an
    /// old SSE connection mid-session. A fresh ephemeral session avoids that.
    private static func makeSseSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }

    // MARK: - Errors

    enum AgentBackendError: Error, LocalizedError {
        case unauthorized
        case httpError(status: Int, message: String)
        case noBody
        case streamEndedWithoutMessage

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Unauthorized – please reconnect"
            case .httpError(let status, let message):
                return "Error \(status): \(message)"
            case .noBody:
                return "No response body"
            case .streamEndedWithoutMessage:
                return "Stream ended without a message event"
            }
        }
    }

    // MARK: - Conversations

    func createConversation(publicKey: String, token: String) async throws -> AgentConversation {
        try await doRequest(.createConversation(publicKey: publicKey, token: token))
    }

    func listConversations(publicKey: String, skip: Int, take: Int, token: String) async throws -> AgentListConversationsResponse {
        try await doRequest(.listConversations(publicKey: publicKey, skip: skip, take: take, token: token))
    }

    func getConversation(id: String, publicKey: String, token: String) async throws -> AgentConversationWithMessages {
        try await doRequest(.getConversation(id: id, publicKey: publicKey, token: token))
    }

    func deleteConversation(id: String, publicKey: String, token: String) async throws {
        let _: AgentEmptyResponse = try await doRequest(.deleteConversation(id: id, publicKey: publicKey, token: token))
    }

    func getStarters(request: AgentGetStartersRequest, token: String) async throws -> AgentGetStartersResponse {
        try await doRequest(.getStarters(request: request, token: token))
    }

    // MARK: - Send Message (non-streaming)

    func sendMessage(convId: String, request: AgentSendMessageRequest, token: String) async throws -> AgentSendMessageResponse {
        try await doRequest(.sendMessage(convId: convId, request: request, token: token))
    }

    // MARK: - Send Message (SSE streaming)
    // NOTE: SSE streaming uses raw URLSession instead of HTTPClient because
    // HTTPClient doesn't support byte-level async streaming (AsyncBytes).
    // All non-streaming REST calls go through HTTPClient via doRequest().

    func sendMessageStream(
        convId: String,
        request: AgentSendMessageRequest,
        token: String
    ) -> AsyncThrowingStream<AgentSSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: Endpoint.agentConversationMessages(id: convId))!
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.addValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if !token.isEmpty {
                        urlRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    urlRequest.httpBody = try AgentBackendClient.sharedEncoder.encode(request)

                    // Fresh ephemeral session per stream. HTTP/2 ignores Connection: close
                    // and reuses the same TCP stream across requests — creating a new session
                    // guarantees a new connection for this SSE stream.
                    let session = AgentBackendClient.makeSseSession()
                    defer { session.finishTasksAndInvalidate() }
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    #if DEBUG
                    logger.debug("SSE response received")
                    #endif

                    guard let httpResponse = response as? HTTPURLResponse else {
                        #if DEBUG
                        logger.error("SSE did not receive an HTTP response")
                        #endif
                        throw AgentBackendError.noBody
                    }
                    #if DEBUG
                    logger.debug("SSE HTTP status: \(httpResponse.statusCode)")
                    logger.debug("SSE Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
                    #endif

                    if httpResponse.statusCode == 401 {
                        #if DEBUG
                        logger.error("SSE returned 401 Unauthorized")
                        #endif
                        throw AgentBackendError.unauthorized
                    }

                    if httpResponse.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        let errMsg = Self.parseErrorMessage(from: body) ?? body
                        #if DEBUG
                        logger.error("SSE HTTP \(httpResponse.statusCode): \(errMsg)")
                        #endif
                        throw AgentBackendError.httpError(status: httpResponse.statusCode, message: errMsg)
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

                    if !contentType.contains("text/event-stream") {
                        // Fallback to JSON
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        if let data = body.data(using: .utf8) {
                            let decoded = try JSONDecoder().decode(AgentSendMessageResponse.self, from: data)
                            if let msg = decoded.message {
                                continuation.yield(.message(msg))
                            }
                        }
                        continuation.finish()
                        return
                    }

                    // Parse SSE
                    var currentEvent = ""
                    var hasMessage = false
                    var lineCount = 0

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            #if DEBUG
                            logger.warning("SSE task cancelled")
                            #endif
                            continuation.finish()
                            return
                        }
                        lineCount += 1
                        #if DEBUG
                        logger.debug("SSE line #\(lineCount): \(String(line.prefix(120)))")
                        #endif

                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .init(charactersIn: "\r"))
                            #if DEBUG
                            logger.debug("SSE data event='\(currentEvent)' json=\(String(jsonStr.prefix(200)))")
                            #endif

                            if let event = self.processSSEEvent(eventName: currentEvent, jsonStr: jsonStr) {
                                if case .message = event {
                                    hasMessage = true
                                }
                                continuation.yield(event)
                            } else {
                                #if DEBUG
                                logger.warning("SSE parser returned nil for event '\(currentEvent)'")
                                #endif
                            }
                            currentEvent = ""
                            continue
                        }
                    }
                    #if DEBUG
                    logger.debug("SSE stream ended. lines=\(lineCount) hasMessage=\(hasMessage)")
                    #endif

                    if !hasMessage {
                        logger.warning("SSE stream ended without message event")
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - SSE Event Parser

    private func processSSEEvent(eventName: String, jsonStr: String) -> AgentSSEEvent? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }

        do {
            switch eventName {
            case "text_delta":
                struct Delta: Decodable { let delta: String }
                let parsed = try AgentBackendClient.sharedDecoder.decode(Delta.self, from: data)
                return .textDelta(parsed.delta)

            case "title":
                struct Title: Decodable { let title: String }
                let parsed = try AgentBackendClient.sharedDecoder.decode(Title.self, from: data)
                return .title(parsed.title)

            case "actions":
                struct Actions: Decodable { let actions: [AgentBackendAction] }
                let parsed = try AgentBackendClient.sharedDecoder.decode(Actions.self, from: data)
                return .actions(parsed.actions)

            case "suggestions":
                struct Suggestions: Decodable { let suggestions: [AgentBackendSuggestion] }
                let parsed = try AgentBackendClient.sharedDecoder.decode(Suggestions.self, from: data)
                return .suggestions(parsed.suggestions)

            case "tx_ready":
                let parsed = try AgentBackendClient.sharedDecoder.decode(AgentTxReady.self, from: data)
                return .txReady(parsed)

            case "tokens":
                // Can be { tokens: [...] } or direct array
                if let wrapper = try? AgentBackendClient.sharedDecoder.decode(TokensWrapper.self, from: data) {
                    return .tokens(wrapper.tokens)
                }
                let tokens = try AgentBackendClient.sharedDecoder.decode([AgentTokenSearchResult].self, from: data)
                return .tokens(tokens)

            case "message":
                struct MessageWrapper: Decodable { let message: AgentBackendMessage }
                let parsed = try AgentBackendClient.sharedDecoder.decode(MessageWrapper.self, from: data)
                return .message(parsed.message)

            case "error":
                struct ErrorPayload: Decodable { let error: String? }
                let parsed = try AgentBackendClient.sharedDecoder.decode(ErrorPayload.self, from: data)
                return .error(parsed.error ?? "stream error")

            case "done":
                return .done

            default:
                logger.info("Unhandled SSE event: \(eventName)")
                return nil
            }
        } catch {
            logger.error("Failed to parse SSE event '\(eventName)': \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Generic Request

    private func doRequest<T: Decodable>(_ target: AgentBackendAPI) async throws -> T {
        let data: Data
        do {
            let response = try await httpClient.request(target)
            data = response.data
        } catch let error as HTTPError {
            throw Self.mapHTTPError(error)
        }

        if data.isEmpty || (String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
            if T.self == AgentEmptyResponse.self {
                return AgentEmptyResponse() as! T
            }
        }

        return try AgentBackendClient.sharedDecoder.decode(T.self, from: data)
    }

    // MARK: - Helpers

    private static func parseErrorMessage(from text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String else {
            return nil
        }
        return error
    }

    private static func mapHTTPError(_ error: HTTPError) -> Error {
        switch error {
        case .statusCode(let status, let data):
            if status == 401 {
                return AgentBackendError.unauthorized
            }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let errMsg = Self.parseErrorMessage(from: text) ?? text
            return AgentBackendError.httpError(
                status: status,
                message: errMsg.isEmpty ? (error.errorDescription ?? "HTTP request failed") : errMsg
            )
        case .invalidResponse, .noData:
            return AgentBackendError.noBody
        default:
            return AgentBackendError.httpError(
                status: 0,
                message: error.errorDescription ?? "HTTP request failed"
            )
        }
    }
}

// MARK: - Helper Types

private struct AgentEmptyResponse: Decodable {}

private struct TokensWrapper: Decodable {
    let tokens: [AgentTokenSearchResult]
}

private enum AgentBackendAPI: TargetType {
    case createConversation(publicKey: String, token: String)
    case listConversations(publicKey: String, skip: Int, take: Int, token: String)
    case getConversation(id: String, publicKey: String, token: String)
    case deleteConversation(id: String, publicKey: String, token: String)
    case getStarters(request: AgentGetStartersRequest, token: String)
    case sendMessage(convId: String, request: AgentSendMessageRequest, token: String)

    var baseURL: URL {
        URL(string: Endpoint.agentBackendUrl)!
    }

    var path: String {
        switch self {
        case .createConversation:
            return "/agent/conversations"
        case .listConversations:
            return "/agent/conversations/list"
        case .getConversation(let id, _, _), .deleteConversation(let id, _, _):
            let safeId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            return "/agent/conversations/\(safeId)"
        case .getStarters:
            return "/agent/starters"
        case .sendMessage(let convId, _, _):
            let safeId = convId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? convId
            return "/agent/conversations/\(safeId)/messages"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .deleteConversation:
            return .delete
        default:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .createConversation(let publicKey, _):
            return .requestParameters(["public_key": publicKey], .jsonEncoding)
        case .listConversations(let publicKey, let skip, let take, _):
            return .requestParameters(["public_key": publicKey, "skip": skip, "take": take], .jsonEncoding)
        case .getConversation(_, let publicKey, _):
            return .requestParameters(["public_key": publicKey], .jsonEncoding)
        case .deleteConversation(_, let publicKey, _):
            return .requestParameters(["public_key": publicKey], .jsonEncoding)
        case .getStarters(let request, _):
            return .requestCodable(request, .jsonEncoding)
        case .sendMessage(_, let request, _):
            return .requestCodable(request, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        var headers = ["Content-Type": "application/json"]
        if !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    private var token: String {
        switch self {
        case .createConversation(_, let token),
             .listConversations(_, _, _, let token),
             .getConversation(_, _, let token),
             .deleteConversation(_, _, let token),
             .getStarters(_, let token),
             .sendMessage(_, _, let token):
            return token
        }
    }
}
