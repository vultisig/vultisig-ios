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
        try await doRequest(
            method: "POST",
            url: Endpoint.agentConversations(),
            token: token,
            body: ["public_key": publicKey]
        )
    }

    func listConversations(publicKey: String, skip: Int, take: Int, token: String) async throws -> AgentListConversationsResponse {
        try await doRequest(
            method: "POST",
            url: Endpoint.agentConversationsList(),
            token: token,
            body: ["public_key": publicKey, "skip": skip, "take": take] as [String: Any]
        )
    }

    func getConversation(id: String, publicKey: String, token: String) async throws -> AgentConversationWithMessages {
        try await doRequest(
            method: "POST",
            url: Endpoint.agentConversation(id: id),
            token: token,
            body: ["public_key": publicKey]
        )
    }

    func deleteConversation(id: String, publicKey: String, token: String) async throws {
        let _: AgentEmptyResponse = try await doRequest(
            method: "DELETE",
            url: Endpoint.agentConversation(id: id),
            token: token,
            body: ["public_key": publicKey]
        )
    }

    func getStarters(request: AgentGetStartersRequest, token: String) async throws -> AgentGetStartersResponse {
        try await doRequest(
            method: "POST",
            url: Endpoint.agentStarters(),
            token: token,
            body: request
        )
    }

    // MARK: - Send Message (non-streaming)

    func sendMessage(convId: String, request: AgentSendMessageRequest, token: String) async throws -> AgentSendMessageResponse {
        try await doRequest(
            method: "POST",
            url: Endpoint.agentConversationMessages(id: convId),
            token: token,
            body: request
        )
    }

    // MARK: - Send Message (SSE streaming)

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
                    print("[AgentBackend] 🌊 SSE response received")
                    #endif

                    guard let httpResponse = response as? HTTPURLResponse else {
                        #if DEBUG
                        print("[AgentBackend] ❌ Not an HTTP response")
                        #endif
                        throw AgentBackendError.noBody
                    }
                    #if DEBUG
                    print("[AgentBackend] 🌊 SSE HTTP status: \(httpResponse.statusCode)")
                    #endif
                    #if DEBUG
                    print("[AgentBackend] 🌊 Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
                    #endif

                    if httpResponse.statusCode == 401 {
                        #if DEBUG
                        print("[AgentBackend] ❌ 401 Unauthorized")
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
                        print("[AgentBackend] ❌ HTTP \(httpResponse.statusCode): \(errMsg)")
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
                            print("[AgentBackend] ⚠️ SSE task cancelled")
                            #endif
                            continuation.finish()
                            return
                        }
                        lineCount += 1
                        #if DEBUG
                        print("[AgentBackend] 📄 SSE line #\(lineCount): \(line.prefix(120))")
                        #endif

                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .init(charactersIn: "\r"))
                            #if DEBUG
                            print("[AgentBackend] 📦 SSE data event='\(currentEvent)' json=\(jsonStr.prefix(200))")
                            #endif

                            if let event = self.processSSEEvent(eventName: currentEvent, jsonStr: jsonStr) {
                                if case .message = event {
                                    hasMessage = true
                                }
                                continuation.yield(event)
                            } else {
                                #if DEBUG
                                print("[AgentBackend] ⚠️ SSE processSSEEvent returned nil for event='\(currentEvent)'")
                                #endif
                            }
                            currentEvent = ""
                            continue
                        }
                    }
                    #if DEBUG
                    print("[AgentBackend] 🏁 SSE stream ended, total lines: \(lineCount), hasMessage: \(hasMessage)")
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

    private func doRequest<T: Decodable>(method: String, url: String, token: String, body: some Encodable) async throws -> T {
        guard let requestUrl = URL(string: url) else {
            throw AgentBackendError.httpError(status: 0, message: "Invalid URL: \(url)")
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try AgentBackendClient.sharedEncoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentBackendError.noBody
        }

        if httpResponse.statusCode == 401 {
            throw AgentBackendError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let text = String(data: data, encoding: .utf8) ?? ""
            let errMsg = Self.parseErrorMessage(from: text) ?? text
            throw AgentBackendError.httpError(status: httpResponse.statusCode, message: errMsg)
        }

        // Handle empty responses (e.g., DELETE)
        if data.isEmpty || (String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
            if T.self == AgentEmptyResponse.self {
                return AgentEmptyResponse() as! T
            }
        }

        return try AgentBackendClient.sharedDecoder.decode(T.self, from: data)
    }

    // Overload for [String: Any] body (non-Encodable dictionaries)
    private func doRequest<T: Decodable>(method: String, url: String, token: String, body: [String: Any]) async throws -> T {
        guard let requestUrl = URL(string: url) else {
            throw AgentBackendError.httpError(status: 0, message: "Invalid URL: \(url)")
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentBackendError.noBody
        }

        if httpResponse.statusCode == 401 {
            throw AgentBackendError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let text = String(data: data, encoding: .utf8) ?? ""
            let errMsg = Self.parseErrorMessage(from: text) ?? text
            throw AgentBackendError.httpError(status: httpResponse.statusCode, message: errMsg)
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
}

// MARK: - Helper Types

private struct AgentEmptyResponse: Decodable {}

private struct TokensWrapper: Decodable {
    let tokens: [AgentTokenSearchResult]
}
