//
//  AgentChatViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import OSLog
import SwiftUI

@MainActor
final class AgentChatViewModel: ObservableObject {

    // MARK: - Published State

    @Published var messages: [AgentChatMessage] = []
    @Published var starters: [String] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var conversationTitle: String?
    @Published var passwordRequired = false
    @Published var isConnected = false

    // MARK: - Private

    private let backendClient = AgentBackendClient()
    private let authService = AgentAuthService.shared
    private let logger = Logger(subsystem: "com.vultisig", category: "AgentChatViewModel")
    private var streamingMessageId: String?
    private var currentTask: Task<Void, Never>?
    private var pendingMessage: String?

    var conversationId: String?

    // MARK: - Hardcoded Fallback Starters

    static let fallbackStarters = [
        "What's my portfolio value?",
        "Show me my balances",
        "What's the price of ETH?",
        "Swap 0.01 ETH for USDC",
        "Check my Bitcoin balance",
        "List my vault chains",
        "What tokens do I have?",
        "Show my transaction history"
    ]

    // MARK: - Send Message

    func sendMessage(_ text: String, vault: Vault) {
        print("[AgentChat] 📤 sendMessage called with text: \(text.prefix(50))...")
        print("[AgentChat] 📤 vault pubKeyECDSA: \(vault.pubKeyECDSA.prefix(20))...")
        
        // Add user message to UI
        let userMsg = AgentChatMessage(
            id: "msg-\(Date().timeIntervalSince1970)",
            role: .user,
            content: text,
            timestamp: Date()
        )
        messages.append(userMsg)
        isLoading = true
        error = nil
        streamingMessageId = nil

        currentTask = Task {
            // Get token if available
            let token = await getValidToken(vault: vault)?.token ?? ""
            
            // If token is empty, we must authenticate first
            if token.isEmpty {
                print("[AgentChat] 🔑 No valid token, prompting for password")
                await MainActor.run {
                    self.pendingMessage = text
                    self.passwordRequired = true
                    self.isLoading = false
                    // Remove the user message from the UI since it hasn't sent yet, we'll append it when it actually sends
                    self.messages.removeLast()
                }
                return
            }

            print("[AgentChat] 🔑 Using token: \(token.prefix(20).description)...")
            
            await executeSendMessage(text: text, vault: vault, token: token)
        }
    }

    private func executeSendMessage(text: String, vault: Vault, token: String) async {
        do {
            // Create conversation if needed
                if conversationId == nil {
                    print("[AgentChat] 🆕 Creating new conversation...")
                    let conv = try await backendClient.createConversation(
                        publicKey: vault.pubKeyECDSA,
                        token: token
                    )
                    conversationId = conv.id
                    print("[AgentChat] ✅ Conversation created: \(conv.id)")
                }
                
                // Fetch starters if needed
                if messages.isEmpty && starters.isEmpty {
                    await loadStarters(vault: vault)
                }
                
                guard let convId = conversationId else {
                    print("[AgentChat] ❌ No conversation ID")
                    throw AgentBackendClient.AgentBackendError.noBody
                }

                // Build context (full context on first message, light on subsequent)
                let context = messages.count <= 2
                    ? AgentContextBuilder.buildContext(vault: vault)
                    : AgentContextBuilder.buildLightContext(vault: vault)
                print("[AgentChat] 📋 Context built (\(messages.count <= 2 ? "full" : "light"))")

                let request = AgentSendMessageRequest(
                    publicKey: vault.pubKeyECDSA,
                    content: text,
                    model: "anthropic/claude-sonnet-4.5",
                    context: context
                )

                if let data = try? JSONEncoder().encode(request), let jsonString = String(data: data, encoding: .utf8) {
                    print("\n[AgentChat] 🐛 Outgoing Request Payload:")
                    print(jsonString)
                    print("-------------------------------------------\n")
                }

                // Stream the response
                print("[AgentChat] 🌊 Starting SSE stream for convId: \(convId)")
                let stream = backendClient.sendMessageStream(
                    convId: convId,
                    request: request,
                    token: token
                )

                var eventCount = 0
                for try await event in stream {
                    if Task.isCancelled {
                        print("[AgentChat] ⚠️ Task cancelled, breaking stream")
                        break
                    }
                    eventCount += 1
                    print("[AgentChat] 📨 SSE event #\(eventCount): \(event)")
                    handleSSEEvent(event, vault: vault)
                }
                print("[AgentChat] 🏁 Stream ended, total events: \(eventCount)")

                isLoading = false

            } catch let error as AgentBackendClient.AgentBackendError {
                print("[AgentChat] ❌ Backend error: \(error.localizedDescription ?? "unknown")")
                handleError(error)
            } catch {
                print("[AgentChat] ❌ General error: \(error) — \(error.localizedDescription)")
                handleError(error)
            }
        }

    // MARK: - Send Action Result

    func sendActionResult(_ result: AgentActionResult, vault: Vault) {
        guard let convId = conversationId else { return }

        isLoading = true

        currentTask = Task {
            do {
                let token = await getValidToken(vault: vault)?.token ?? ""

                let request = AgentSendMessageRequest(
                    publicKey: vault.pubKeyECDSA,
                    model: "anthropic/claude-sonnet-4.5",
                    actionResult: result
                )

                let stream = backendClient.sendMessageStream(
                    convId: convId,
                    request: request,
                    token: token
                )

                for try await event in stream {
                    if Task.isCancelled { break }
                    handleSSEEvent(event, vault: vault)
                }

                isLoading = false

            } catch {
                handleError(error)
            }
        }
    }

    // MARK: - Load Existing Conversation

    func loadConversation(id: String, vault: Vault) async {
        conversationId = id
        isLoading = true

        do {
            let token = await getValidToken(vault: vault)?.token ?? ""

            let conv = try await backendClient.getConversation(
                id: id,
                publicKey: vault.pubKeyECDSA,
                token: token
            )

            conversationTitle = conv.title

            // Convert backend messages to chat messages
            messages = conv.messages.map { msg in
                AgentChatMessage(
                    id: msg.id,
                    role: msg.role == "user" ? .user : .assistant,
                    content: msg.content,
                    timestamp: ISO8601DateFormatter().date(from: msg.createdAt) ?? Date()
                )
            }

            isLoading = false
        } catch {
            logger.error("Failed to load conversation: \(error.localizedDescription)")
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Auth

    func signIn(vault: Vault, password: String) async {
        print("[AgentChat] 🔐 signIn called with password length: \(password.count)")
        do {
            _ = try await authService.signIn(vault: vault, password: password)
            print("[AgentChat] ✅ signIn succeeded")
            isConnected = true
            passwordRequired = false
            
            if let pending = pendingMessage {
                print("[AgentChat] 📤 Sending pending message after login")
                let msgToSend = pending
                pendingMessage = nil
                self.sendMessage(msgToSend, vault: vault)
            }
        } catch {
            print("[AgentChat] ❌ signIn failed: \(error)")
            self.error = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func checkConnection(vault: Vault) {
        // Agent backend uses public_key for identity, no auth token needed
        print("[AgentChat] 🔌 checkConnection: always connected (public_key auth)")
        isConnected = true
    }
    
    // MARK: - Load Starters
    
    func loadStarters(vault: Vault) async {
        let token = await getValidToken(vault: vault)
        
        do {
            let context = AgentContextBuilder.buildContext(vault: vault)
            let request = AgentGetStartersRequest(
                publicKey: vault.pubKeyECDSA,
                context: context
            )
            
            let response = try await backendClient.getStarters(
                request: request,
                token: token?.token ?? ""
            )
            
            if response.starters.isEmpty {
                starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
            } else {
                starters = Array(response.starters.shuffled().prefix(4))
            }
        } catch {
            logger.warning("Failed to load starters, using fallback: \(error.localizedDescription)")
            starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
        }
    }

    func disconnect(vault: Vault) async {
        await authService.disconnect(vaultPubKey: vault.pubKeyECDSA)
        isConnected = false
    }

    // MARK: - Cancel

    func cancelRequest() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        streamingMessageId = nil
    }

    func dismissError() {
        error = nil
    }

    // MARK: - SSE Event Handling

    private func handleSSEEvent(_ event: AgentSSEEvent, vault: Vault? = nil) {
        switch event {
        case .textDelta(let delta):
            handleTextDelta(delta)

        case .title(let title):
            conversationTitle = title

        case .actions(let actions):
            if let vault = AppViewModel.shared.selectedVault {
                handleActions(actions, vault: vault)
            }

        case .suggestions:
            // Suggestions are displayed in the conversation starters, not inline
            break

        case .txReady:
            // TODO: Handle tx_ready events for transaction signing
            break

        case .tokens(let tokenResults):
            // Attach token results to the current streaming message
            if let streamId = streamingMessageId,
               let idx = messages.firstIndex(where: { $0.id == streamId }) {
                messages[idx].tokenResults = tokenResults
            }

        case .message(let backendMsg):
            finalizeStreamingMessage(with: backendMsg)

        case .error(let errorMsg):
            streamingMessageId = nil
            let normalized = normalizeErrorMessage(errorMsg)
            if normalized == "agent stopped" {
                appendAssistantMessage("Agent stopped. Send a new message when you're ready.")
            } else {
                error = normalized
            }
            isLoading = false

        case .done:
            isLoading = false
        }
    }

    private func handleTextDelta(_ delta: String) {
        if let existingId = streamingMessageId,
           let idx = messages.firstIndex(where: { $0.id == existingId }) {
            messages[idx].content += delta
        } else {
            let msgId = "streaming-\(Date().timeIntervalSince1970)"
            streamingMessageId = msgId
            let streamMsg = AgentChatMessage(
                id: msgId,
                role: .assistant,
                content: delta,
                timestamp: Date()
            )
            messages.append(streamMsg)
            isLoading = false
        }
    }

    private func handleActions(_ actions: [AgentBackendAction], vault: Vault) {
        for action in actions {
            // Add tool call status message
            let toolCallMsg = AgentChatMessage(
                id: "tool-call-\(action.id)",
                role: .assistant,
                content: "",
                timestamp: Date(),
                toolCall: AgentToolCallInfo(
                    actionType: action.type,
                    title: action.title,
                    params: action.params,
                    status: .running
                )
            )
            messages.append(toolCallMsg)

            // Auto-execute simple tools
            if action.autoExecute {
                handleAutoExecuteAction(action, vault: vault)
            }
        }
    }

    private func handleAutoExecuteAction(_ action: AgentBackendAction, vault: Vault) {
        let toolCallId = "tool-call-\(action.id)"

        Task {
            let result = await AgentToolExecutor.execute(action: action, vault: vault)
            
            if let idx = messages.firstIndex(where: { $0.id == toolCallId }) {
                messages[idx].toolCall?.status = result.success ? .success : .error
                messages[idx].toolCall?.resultData = result.data
                messages[idx].toolCall?.error = result.error
            }
            
            // Stream the result back
            sendActionResult(result, vault: vault)
        }
    }

    private func finalizeStreamingMessage(with backendMsg: AgentBackendMessage) {
        if let streamId = streamingMessageId,
           let idx = messages.firstIndex(where: { $0.id == streamId }) {
            let oldMsg = messages[idx]
            messages[idx] = AgentChatMessage(
                id: backendMsg.id,
                role: oldMsg.role,
                content: backendMsg.content,
                timestamp: oldMsg.timestamp,
                toolCall: oldMsg.toolCall,
                txStatus: oldMsg.txStatus,
                tokenResults: oldMsg.tokenResults
            )
        } else if !backendMsg.content.trimmingCharacters(in: .whitespaces).isEmpty {
            let msg = AgentChatMessage(
                id: backendMsg.id,
                role: .assistant,
                content: backendMsg.content,
                timestamp: ISO8601DateFormatter().date(from: backendMsg.createdAt) ?? Date()
            )
            messages.append(msg)
        }
        streamingMessageId = nil
        isLoading = false
    }

    private func appendAssistantMessage(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let msg = AgentChatMessage(
            id: "msg-\(Date().timeIntervalSince1970)",
            role: .assistant,
            content: content,
            timestamp: Date()
        )
        messages.append(msg)
    }

    // MARK: - Helpers

    private func getValidToken(vault: Vault) async -> AgentAuthToken? {
        print("[AgentChat] 🔑 getValidToken: checking cached token for \(vault.pubKeyECDSA.prefix(20))...")
        if let token = authService.getCachedToken(vaultPubKey: vault.pubKeyECDSA) {
            print("[AgentChat] 🔑 getValidToken: found cached token, expires \(token.expiresAt)")
            return token
        }
        print("[AgentChat] 🔑 getValidToken: no cached token, trying to refresh...")
        let refreshed = await authService.refreshIfNeeded(vaultPubKey: vault.pubKeyECDSA)
        print("[AgentChat] 🔑 getValidToken: refresh result = \(refreshed != nil ? "token found" : "nil")")
        return refreshed
    }

    private func handleError(_ error: Error) {
        print("[AgentChat] ⚠️ handleError: \(error) — \(error.localizedDescription)")
        streamingMessageId = nil
        isLoading = false

        if case AgentBackendClient.AgentBackendError.unauthorized = error {
            print("[AgentChat] ⚠️ handleError: unauthorized, showing password prompt")
            passwordRequired = true
            self.error = nil
        } else {
            self.error = error.localizedDescription
        }

        logger.error("Agent error: \(error.localizedDescription)")
    }

    private func normalizeErrorMessage(_ error: String) -> String {
        let lower = error.lowercased()
        let cancelPatterns = ["context canceled", "context cancelled", "user cancelled", "user canceled", "agent stopped"]
        for pattern in cancelPatterns {
            if lower.contains(pattern) {
                return "agent stopped"
            }
        }
        return error
    }
}
