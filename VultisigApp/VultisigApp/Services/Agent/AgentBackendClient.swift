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
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    print("[AgentBackend] 🌊 SSE response received")

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("[AgentBackend] ❌ Not an HTTP response")
                        throw AgentBackendError.noBody
                    }
                    print("[AgentBackend] 🌊 SSE HTTP status: \(httpResponse.statusCode)")
                    print("[AgentBackend] 🌊 Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")

                    if httpResponse.statusCode == 401 {
                        print("[AgentBackend] ❌ 401 Unauthorized")
                        throw AgentBackendError.unauthorized
                    }

                    if httpResponse.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        let errMsg = Self.parseErrorMessage(from: body) ?? body
                        print("[AgentBackend] ❌ HTTP \(httpResponse.statusCode): \(errMsg)")
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
                            print("[AgentBackend] ⚠️ SSE task cancelled")
                            continuation.finish()
                            return
                        }
                        lineCount += 1
                        print("[AgentBackend] 📄 SSE line #\(lineCount): \(line.prefix(120))")

                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .init(charactersIn: "\r"))
                            print("[AgentBackend] 📦 SSE data event='\(currentEvent)' json=\(jsonStr.prefix(200))")

                            if let event = self.processSSEEvent(eventName: currentEvent, jsonStr: jsonStr) {
                                if case .message = event {
                                    hasMessage = true
                                }
                                continuation.yield(event)
                            } else {
                                print("[AgentBackend] ⚠️ SSE processSSEEvent returned nil for event='\(currentEvent)'")
                            }
                            currentEvent = ""
                            continue
                        }
                    }
                    print("[AgentBackend] 🏁 SSE stream ended, total lines: \(lineCount), hasMessage: \(hasMessage)")

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
                let parsed = try JSONDecoder().decode(Delta.self, from: data)
                return .textDelta(parsed.delta)

            case "title":
                struct Title: Decodable { let title: String }
                let parsed = try JSONDecoder().decode(Title.self, from: data)
                return .title(parsed.title)

            case "actions":
                struct Actions: Decodable { let actions: [AgentBackendAction] }
                let parsed = try JSONDecoder().decode(Actions.self, from: data)
                return .actions(parsed.actions)

            case "suggestions":
                struct Suggestions: Decodable { let suggestions: [AgentBackendSuggestion] }
                let parsed = try JSONDecoder().decode(Suggestions.self, from: data)
                return .suggestions(parsed.suggestions)

            case "tx_ready":
                let parsed = try JSONDecoder().decode(AgentTxReady.self, from: data)
                return .txReady(parsed)

            case "tokens":
                // Can be { tokens: [...] } or direct array
                if let wrapper = try? JSONDecoder().decode(TokensWrapper.self, from: data) {
                    return .tokens(wrapper.tokens)
                }
                let tokens = try JSONDecoder().decode([AgentTokenSearchResult].self, from: data)
                return .tokens(tokens)

            case "message":
                struct MessageWrapper: Decodable { let message: AgentBackendMessage }
                let parsed = try JSONDecoder().decode(MessageWrapper.self, from: data)
                return .message(parsed.message)

            case "error":
                struct ErrorPayload: Decodable { let error: String? }
                let parsed = try JSONDecoder().decode(ErrorPayload.self, from: data)
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
        request.httpBody = try JSONEncoder().encode(body)

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

        return try JSONDecoder().decode(T.self, from: data)
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

        return try JSONDecoder().decode(T.self, from: data)
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
