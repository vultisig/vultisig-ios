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

    @Published var pendingSendTx: SendTransaction?
    @Published var shouldShowPairingSheet = false
    @Published var showFastVaultPasswordPrompt = false
    @Published var activeKeysignPayload: KeysignPayload?
    var activeSignTxCallId: String?

    // MARK: - Private

    private let backendClient = AgentBackendClient()
    private let authService = AgentAuthService.shared
    private let logger = Logger(subsystem: "com.vultisig", category: "AgentChatViewModel")
    private var streamingMessageId: String?
    private var currentTask: Task<Void, Never>?
    private var pendingMessage: String?
    private var cachedFastVaultPassword: String?

    // SSE delta buffering — accumulate characters and flush at ~25 Hz
    private var streamingBuffer: String = ""
    private var flushTimer: Timer?

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
        #if DEBUG
        print("[AgentChat] 📤 sendMessage called")
        #endif

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
                #if DEBUG
                print("[AgentChat] 🔑 No valid token, prompting for password")
                #endif
                await MainActor.run {
                    self.pendingMessage = text
                    self.passwordRequired = true
                    self.isLoading = false
                    // Remove the user message from the UI since it hasn't sent yet, we'll append it when it actually sends
                    self.messages.removeAll { $0.id == userMsg.id }
                }
                return
            }

            #if DEBUG
            print("[AgentChat] 🔑 Using token: \(token.prefix(20).description)...")
            #endif

            await executeSendMessage(text: text, vault: vault, token: token)
        }
    }

    private func executeSendMessage(text: String, vault: Vault, token: String) async {
        do {
            // Create conversation if needed
            if conversationId == nil {
                #if DEBUG
                print("[AgentChat] 🆕 Creating new conversation...")
                #endif
                let conv = try await backendClient.createConversation(
                    publicKey: vault.pubKeyECDSA,
                    token: token
                )
                conversationId = conv.id
                #if DEBUG
                print("[AgentChat] ✅ Conversation created: \(conv.id)")
                #endif

                await primeMCPSession(vault: vault, token: token, convId: conv.id)
            }

            // Fetch starters if needed
            if messages.isEmpty && starters.isEmpty {
                await loadStarters(vault: vault)
            }

            guard let convId = conversationId else {
                #if DEBUG
                print("[AgentChat] ❌ No conversation ID")
                #endif
                throw AgentBackendClient.AgentBackendError.noBody
            }

            // Build context (full context on first message, light on subsequent)
            let context: AgentMessageContext
            if messages.count <= 2 {
                context = AgentContextBuilder.buildContext(vault: vault)  // @MainActor, not async
            } else {
                context = AgentContextBuilder.buildLightContext(vault: vault)  // @MainActor, not async
            }
            #if DEBUG
            print("[AgentChat] 📋 Context built (\(messages.count <= 2 ? "full" : "light"))")
            #endif

            let request = AgentSendMessageRequest(
                publicKey: vault.pubKeyECDSA,
                content: text,
                model: "anthropic/claude-sonnet-4.5",
                context: context
            )

            if let data = try? JSONEncoder().encode(request), let jsonString = String(data: data, encoding: .utf8) {
                #if DEBUG
                print("\n[AgentChat] 🐛 Outgoing Request Payload:")
                #endif
                #if DEBUG
                print(jsonString)
                #endif
                #if DEBUG
                print("-------------------------------------------\n")
                #endif
            }

            // Stream the response
            #if DEBUG
            print("[AgentChat] 🌊 Starting SSE stream for convId: \(convId)")
            #endif
            let stream = backendClient.sendMessageStream(
                convId: convId,
                request: request,
                token: token
            )

            var eventCount = 0
            for try await event in stream {
                if Task.isCancelled {
                    #if DEBUG
                    print("[AgentChat] ⚠️ Task cancelled, breaking stream")
                    #endif
                    break
                }
                eventCount += 1
                #if DEBUG
                print("[AgentChat] 📨 SSE event #\(eventCount): \(event)")
                #endif
                handleSSEEvent(event, vault: vault)
            }
            #if DEBUG
            print("[AgentChat] 🏁 Stream ended, total events: \(eventCount)")
            #endif

            isLoading = false

        } catch let error as AgentBackendClient.AgentBackendError {
            #if DEBUG
            print("[AgentChat] ❌ Backend error: \(error.localizedDescription)")
            #endif
            handleError(error)
        } catch {
            #if DEBUG
            print("[AgentChat] ❌ General error: \(error) — \(error.localizedDescription)")
            #endif
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

            await primeMCPSession(vault: vault, token: token, convId: id)

            // Convert backend messages to chat messages
            messages = conv.messages.map { msg in
                AgentChatMessage(
                    id: msg.id,
                    role: msg.role == "user" ? .user : .assistant,
                    content: msg.content,
                    timestamp: AgentBackendClient.parseISO8601(msg.createdAt) ?? Date()
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
        #if DEBUG
        print("[AgentChat] 🔐 signIn called with password length: \(password.count)")
        #endif
        do {
            _ = try await authService.signIn(vault: vault, password: password)
            #if DEBUG
            print("[AgentChat] ✅ signIn succeeded")
            #endif
            isConnected = true
            passwordRequired = false
            cachedFastVaultPassword = password  // Cache for headless keysign reuse

            if let pending = pendingMessage {
                #if DEBUG
                print("[AgentChat] 📤 Sending pending message after login")
                #endif
                let msgToSend = pending
                pendingMessage = nil
                self.sendMessage(msgToSend, vault: vault)
            }
        } catch {
            #if DEBUG
            print("[AgentChat] ❌ signIn failed: \(error)")
            #endif
            self.error = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func checkConnection(vault _: Vault) {
        // Agent backend uses public_key for identity, no auth token needed
        #if DEBUG
        print("[AgentChat] 🔌 checkConnection: always connected (public_key auth)")
        #endif
        isConnected = true
    }

    // MARK: - Load Starters

    func loadStarters(vault: Vault) async {
        let token = await getValidToken(vault: vault)

        do {
            let context = AgentContextBuilder.buildContext(vault: vault)  // @MainActor, not async
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
        cachedFastVaultPassword = nil
        isConnected = false
    }

    // MARK: - Cancel

    func cancelRequest() {
        stopFlushTimer()
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        streamingMessageId = nil
        streamingBuffer = ""
    }

    func dismissError() {
        error = nil
    }

    // MARK: - Delete Conversation

    @Published var conversationDeleted = false

    func deleteCurrentConversation(vault: Vault) {
        guard let convId = conversationId else { return }
        Task {
            let token = await getValidToken(vault: vault)
            do {
                try await backendClient.deleteConversation(
                    id: convId,
                    publicKey: vault.pubKeyECDSA,
                    token: token?.token ?? ""
                )
                conversationDeleted = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - SSE Event Handling

    private func handleSSEEvent(_ event: AgentSSEEvent, vault: Vault? = nil) {
        switch event {
        case .textDelta(let delta):
            handleTextDelta(delta)

        case .title(let title):
            conversationTitle = title

        case .actions(let actions):
            let effectiveVault = vault ?? AppViewModel.shared.selectedVault
            if let v = effectiveVault {
                handleActions(actions, vault: v)
            }

        case .suggestions:
            // Suggestions are displayed in the conversation starters, not inline
            break

        case .txReady(let txReady):
            handleTxReady(txReady)

        case .tokens(let tokenResults):
            // Attach token results to the current streaming message
            if let streamId = streamingMessageId,
               let idx = messages.firstIndex(where: { $0.id == streamId }) {
                messages[idx].tokenResults = tokenResults
            }

        case .message(let backendMsg):
            finalizeStreamingMessage(with: backendMsg)

        case .error(let errorMsg):
            // Bug fix: stop the flush timer so it doesn't keep running after the stream ends
            stopFlushTimer()
            streamingBuffer = ""
            // Mark the in-flight message as finished so it renders Markdown
            if let streamId = streamingMessageId,
               let idx = messages.firstIndex(where: { $0.id == streamId }) {
                messages[idx].isStreaming = false
            }
            streamingMessageId = nil
            let normalized = normalizeErrorMessage(errorMsg)
            if normalized == "agent stopped" {
                appendAssistantMessage("Agent stopped. Send a new message when you're ready.")
            } else {
                error = normalized
            }
            isLoading = false

        case .done:
            // Bug fix: stop the flush timer and finalize any buffered text
            stopFlushTimer()
            if !streamingBuffer.isEmpty,
               let streamId = streamingMessageId,
               let idx = messages.firstIndex(where: { $0.id == streamId }) {
                messages[idx].content = streamingBuffer
                messages[idx].isStreaming = false
            } else if let streamId = streamingMessageId,
                      let idx = messages.firstIndex(where: { $0.id == streamId }) {
                messages[idx].isStreaming = false
            }
            streamingBuffer = ""
            streamingMessageId = nil
            isLoading = false
        }
    }

    private func handleTextDelta(_ delta: String) {
        streamingBuffer += delta

        if streamingMessageId == nil {
            // No pre-seeded message: create one and start streaming
            let msgId = "streaming-\(Date().timeIntervalSince1970)"
            streamingMessageId = msgId
            #if DEBUG
            print("[AgentChat] 💬 Created new streaming message id: \(msgId)")
            #endif
            let streamMsg = AgentChatMessage(
                id: msgId,
                role: .assistant,
                content: "",
                timestamp: Date(),
                isStreaming: true
            )
            messages.append(streamMsg)
            isLoading = false
        } else if let streamId = streamingMessageId,
                  let idx = messages.firstIndex(where: { $0.id == streamId }),
                  !messages[idx].isStreaming {
            // Bug fix: pre-seeded seed message (from auto-execute) was not marked isStreaming.
            // Mark it now so the view switches to plain-text mode immediately.
            messages[idx].isStreaming = true
        }

        // Always ensure the timer is running (pre-seeded paths skip the block above)
        startFlushTimer()
    }

    private func startFlushTimer() {
        guard flushTimer == nil else { return }
        // ~25 Hz flush rate — smooth without hammering main thread.
        // Use a DispatchQueue.main scheduled timer so the closure runs on MainActor
        // without needing an explicit @MainActor annotation on the block.
        flushTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.flushStreamingBuffer() }
        }
    }

    private func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    @MainActor
    private func flushStreamingBuffer() {
        guard !streamingBuffer.isEmpty,
              let streamId = streamingMessageId,
              let idx = messages.firstIndex(where: { $0.id == streamId }) else { return }
        messages[idx].content = streamingBuffer
    }

    private func handleActions(_ actions: [AgentBackendAction], vault: Vault) {
        var autoExecuteActions: [AgentBackendAction] = []

        for action in actions {
            // Add tool call status message
            let toolCallMsg = AgentChatMessage(
                id: "tool-call-\(action.id)",
                role: .assistant,
                content: "",
                timestamp: Date(),
                toolCall: AgentToolCallInfo(
                    actionType: action.type,
                    title: formatActionTitle(action.type, title: action.title),
                    params: action.params,
                    status: .running
                )
            )
            messages.append(toolCallMsg)

            if action.type == "build_send_tx" {
                self.createPendingSendTx(from: action.params, vault: vault)
            } else if action.type == "sign_tx" {
                self.activeSignTxCallId = "tool-call-\(action.id)"
                self.confirmSignTx(vault: vault)
            }

            if action.autoExecute {
                autoExecuteActions.append(action)
            }
        }

        // Execute all auto-execute actions
        if !autoExecuteActions.isEmpty {
            if autoExecuteActions.count == 1 {
                handleAutoExecuteAction(autoExecuteActions[0], vault: vault)
            } else {
                handleAutoExecuteActions(autoExecuteActions, vault: vault)
            }
        }
    }

    private func handleAutoExecuteAction(_ action: AgentBackendAction, vault: Vault) {
        let toolCallId = "tool-call-\(action.id)"

        Task { @MainActor in
            let result = await AgentToolExecutor.execute(action: action, vault: vault)

            if let idx = self.messages.firstIndex(where: { $0.id == toolCallId }) {
                self.messages[idx].toolCall?.status = result.success ? .success : .error
                self.messages[idx].toolCall?.resultData = result.data
                self.messages[idx].toolCall?.error = result.error
            }

            // Plant a seed message marked isStreaming: true before streaming the result back
            self.isLoading = true
            let seedId = "streaming-\(Date().timeIntervalSince1970)"
            self.streamingMessageId = seedId
            self.messages.append(AgentChatMessage(
                id: seedId,
                role: .assistant,
                content: "",
                timestamp: Date(),
                isStreaming: true    // Bug fix: must be true so view and handleTextDelta handle this correctly
            ))

            // Stream the result back
            self.sendActionResult(result, vault: vault)
        }
    }

    private func handleAutoExecuteActions(_ actions: [AgentBackendAction], vault: Vault) {
        // Execute all actions locally (no backend round-trip per action), then
        // send a SINGLE aggregated action result. This prevents N×backend calls
        // (e.g. "remove all 22 chains" becomes 1 request instead of 22).
        Task { @MainActor in
            var allSucceeded = true
            var aggregatedData: [String: AnyCodable] = [:]
            var errors: [String] = []
            let actionType = actions.first?.type ?? "batch"

            for action in actions {
                if Task.isCancelled { break }

                let toolCallId = "tool-call-\(action.id)"
                let result = await AgentToolExecutor.execute(action: action, vault: vault)

                if let idx = self.messages.firstIndex(where: { $0.id == toolCallId }) {
                    self.messages[idx].toolCall?.status = result.success ? .success : .error
                    self.messages[idx].toolCall?.resultData = result.data
                    self.messages[idx].toolCall?.error = result.error
                }

                if !result.success {
                    allSucceeded = false
                    errors.append(result.error ?? "unknown error for action \(action.id)")
                }

                if let outData = result.data {
                    for (k, v) in outData {
                        aggregatedData["\(action.id)_\(k)"] = v
                    }
                }
            }

            // Send ONE aggregated result back to the backend
            var summaryData: [String: AnyCodable] = [
                "completed": AnyCodable(actions.count),
                "succeeded": AnyCodable(allSucceeded ? actions.count : actions.count - errors.count),
                "failed": AnyCodable(errors.count)
            ]
            if !aggregatedData.isEmpty {
                summaryData["results"] = AnyCodable(aggregatedData)
            }
            if !errors.isEmpty {
                summaryData["errors"] = AnyCodable(errors)
            }

            let aggregatedResult = AgentActionResult(
                action: actionType,
                success: allSucceeded,
                data: summaryData,
                error: errors.isEmpty ? nil : errors.joined(separator: "; ")
            )

            // Plant an empty "seed" assistant message and register it as the
            // current streaming message BEFORE calling sendActionResult.
            //
            // This achieves two things:
            //   1. isLoading = true → spinner shows during the gap
            //   2. streamingMessageId is set so the second SSE stream's
            //      text_delta events stream character-by-character into the
            //      seed message (real-time typing effect). If the backend
            //      sends a `message` event instead, finalizeStreamingMessage
            //      replaces the seed cleanly with the real content.
            await MainActor.run {
                self.isLoading = true
                let seedId = "streaming-\(Date().timeIntervalSince1970)"
                self.streamingMessageId = seedId
                self.messages.append(AgentChatMessage(
                    id: seedId,
                    role: .assistant,
                    content: "",
                    timestamp: Date(),
                    isStreaming: true    // Bug fix: must be true so view and handleTextDelta handle this correctly
                ))
            }
            self.sendActionResult(aggregatedResult, vault: vault)
        }
    }

    private func finalizeStreamingMessage(with backendMsg: AgentBackendMessage) {
        #if DEBUG
        print("[AgentChat] 🏁 Finalizing streaming message id: \(backendMsg.id). Current streamingMessageId: \(streamingMessageId ?? "nil")")
        #endif
        // Stop timer and apply any remaining buffered text before replacing with final content
        stopFlushTimer()
        streamingBuffer = ""

        if let streamId = streamingMessageId,
           let idx = messages.firstIndex(where: { $0.id == streamId }) {
            let oldMsg = messages[idx]
            // isStreaming = false → view will now render full Markdown
            messages[idx] = AgentChatMessage(
                id: backendMsg.id,
                role: oldMsg.role,
                content: backendMsg.content,
                timestamp: oldMsg.timestamp,
                toolCall: oldMsg.toolCall,
                txStatus: oldMsg.txStatus,
                tokenResults: oldMsg.tokenResults,
                txProposal: oldMsg.txProposal,
                isStreaming: false
            )
        } else if !backendMsg.content.trimmingCharacters(in: .whitespaces).isEmpty {
            let msg = AgentChatMessage(
                id: backendMsg.id,
                role: .assistant,
                content: backendMsg.content,
                timestamp: AgentBackendClient.parseISO8601(backendMsg.createdAt) ?? Date()
            )
            messages.append(msg)
        }
        streamingMessageId = nil
        isLoading = false
    }

    private func handleTxReady(_ txReady: AgentTxReady) {
        let msg = AgentChatMessage(
            id: "tx-proposal-\(Date().timeIntervalSince1970)",
            role: .assistant,
            content: "",
            timestamp: Date(),
            txProposal: txReady
        )
        messages.append(msg)
        isLoading = false
    }

    func acceptTxProposal(_ proposal: AgentTxReady, vault _: Vault) {
        #if DEBUG
        print("[AgentChat] 💳 User ACCEPTED transaction. Not fully implemented yet. keysignPayload length: \(proposal.keysignPayload?.count ?? 0)")
        #endif
        appendAssistantMessage("Transaction accepted. Launching keysign...")

        // TODO: This is where we will route the keysign payload to the Vultisig router in Phase 13.
        isLoading = false
    }

    func rejectTxProposal(_: AgentTxReady, vault: Vault) {
        #if DEBUG
        print("[AgentChat] ❌ User REJECTED transaction.")
        #endif
        sendMessage("Cancel the transaction. I do not want to execute it.", vault: vault)
    }

    func handleTxBroadcasted(txid: String, vault: Vault) {
        let callId = activeSignTxCallId

        // Send the result to AI
        let result = AgentActionResult(
            action: "sign_tx",
            success: true,
            data: ["txid": AnyCodable(txid)]
        )

        MainActor.assumeIsolated {
            self.shouldShowPairingSheet = false
            self.pendingSendTx = nil
            self.activeSignTxCallId = nil

            // Update the tool-call message bubble if we have a matching ID
            if let callId, let idx = self.messages.firstIndex(where: { $0.id == callId }) {
                self.messages[idx].toolCall?.status = .success
                self.messages[idx].toolCall?.resultData = ["txid": AnyCodable(txid)]
            }

            // Always append the txid to chat so it's visible to the user
            self.appendAssistantMessage("✅ Transaction broadcast!\nTxID: `\(txid)`")

            self.sendActionResult(result, vault: vault)
        }
    }

    func confirmSignTx(vault: Vault) {
        #if DEBUG
        print("[AgentChat] 🔐 confirmSignTx called. pendingSendTx=\(pendingSendTx != nil ? "SET (\(pendingSendTx!.coin.ticker) on \(pendingSendTx!.coin.chain.name))" : "NIL")")
        #endif
        guard let pendingSendTx else {
            #if DEBUG
            print("[AgentChat] ❌ confirmSignTx: pendingSendTx is nil, returning early")
            #endif
            return
        }

        #if DEBUG
        print("[AgentChat] 🔐 confirmSignTx: isFastVault=\(vault.isFastVault), cachedPassword=\(cachedFastVaultPassword != nil ? "SET" : "NIL")")
        #endif
        if vault.isFastVault {
            // Fully headless: use cached password from signIn, no sheets at all
            if let password = cachedFastVaultPassword, !password.isEmpty {
                #if DEBUG
                print("[AgentChat] 🔐 confirmSignTx: using cached password, calling executeFastVaultKeysign")
                #endif
                executeFastVaultKeysign(password: password, vault: vault)
            } else {
                // Fallback: prompt for password if not cached
                #if DEBUG
                print("[AgentChat] 🔐 confirmSignTx: no cached password, showing FastVaultPasswordPrompt")
                #endif
                self.showFastVaultPasswordPrompt = true
            }
        } else {
            Task {
                await MainActor.run {
                    self.isLoading = true
                    self.appendAssistantMessage("Generating keysign payload...")
                }

                do {
                    let logic = SendCryptoVerifyLogic()

                    await BalanceService.shared.updateBalance(for: pendingSendTx.coin)
                    let feeResult = try await logic.calculateFee(tx: pendingSendTx)
                    pendingSendTx.fee = feeResult.fee
                    pendingSendTx.gas = feeResult.gas

                    let result = logic.validateBalanceWithFee(tx: pendingSendTx)
                    if !result.isValid {
                        throw HelperError.runtimeError(result.errorMessage ?? "Insufficient balance to cover fee.")
                    }

                    try await logic.validateUtxosIfNeeded(tx: pendingSendTx)
                    let payload = try await logic.buildKeysignPayload(tx: pendingSendTx, vault: vault)

                    await MainActor.run {
                        self.isLoading = false
                        self.activeKeysignPayload = payload
                        self.shouldShowPairingSheet = true
                    }
                } catch {
                    await MainActor.run {
                        self.isLoading = false
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    func executeFastVaultKeysign(password: String, vault: Vault) {
        guard let tx = pendingSendTx else {
            #if DEBUG
            print("[AgentChat] ❌ executeFastVaultKeysign: pendingSendTx is nil")
            #endif
            return
        }

        // Cache password for future transactions in this session
        if cachedFastVaultPassword == nil {
            cachedFastVaultPassword = password
        }

        Task {
            await MainActor.run {
                self.isLoading = true
                self.appendAssistantMessage("Signing and broadcasting transaction...")
            }

            do {
                let logic = SendCryptoVerifyLogic()

                // 1. Fetch fees
                await BalanceService.shared.updateBalance(for: tx.coin)
                let feeResult = try await logic.calculateFee(tx: tx)
                tx.fee = feeResult.fee
                tx.gas = feeResult.gas

                #if DEBUG
                print("[AgentChat] 💰 Balance check: rawBalance='\(tx.coin.rawBalance)', decimals=\(tx.coin.decimals)")
                #endif
                #if DEBUG
                print("[AgentChat] 💰 amount=\(tx.amount), amountInRaw=\(tx.amountInRaw)")
                #endif
                #if DEBUG
                print("[AgentChat] 💰 fee=\(tx.fee), gas=\(tx.gas)")
                #endif
                #if DEBUG
                print("[AgentChat] 💰 isNativeToken=\(tx.coin.isNativeToken), sendMaxAmount=\(tx.sendMaxAmount)")
                #endif

                let validationResult = logic.validateBalanceWithFee(tx: tx)
                if !validationResult.isValid {
                    let errStr = validationResult.errorMessage ?? "Insufficient balance to cover fee."
                    #if DEBUG
                    print("[AgentChat] ❌ Balance validation FAILED: \(errStr)")
                    #endif
                    let localizedErr = NSLocalizedString(errStr, comment: "")
                    throw HelperError.runtimeError(localizedErr == errStr ? errStr : localizedErr)
                }

                try await logic.validateUtxosIfNeeded(tx: tx)

                // 2. Validate form
                let keysignPayload = try await logic.buildKeysignPayload(tx: tx, vault: vault)

                // 3. Generate Keysign Messages (Matches KeysignDiscoveryViewModel flow)
                let finalPayload = keysignPayload.coin.chain == .solana ?
                try await BlockChainService.shared.refreshSolanaBlockhash(for: keysignPayload) : keysignPayload
                let keysignFactory = KeysignMessageFactory(payload: finalPayload)
                let preSignedImageHash = try keysignFactory.getKeysignMessages()
                let keysignMessages = preSignedImageHash.sorted()

                guard !keysignMessages.isEmpty else {
                    throw HelperError.runtimeError("No message need to be signed")
                }

                // 4. FastVault Keysign execution
                let input = FastVaultKeysignInput(
                    vault: vault,
                    keysignMessages: keysignMessages,
                    derivePath: finalPayload.coin.coinType.derivationPath(),
                    isECDSA: finalPayload.coin.chain.signingKeyType == .ECDSA,
                    vaultPassword: password,
                    chain: finalPayload.coin.chain.name
                )

                let result = try await FastVaultKeysignService.shared.keysign(input: input)
                #if DEBUG
                print("[AgentChat] ✅ Keysign returned \(result.signatures.count) signature(s)")
                #endif

                // 5. Broadcast Transaction
                await MainActor.run {
                    self.appendAssistantMessage("Transaction signed! Broadcasting to network...")
                }

                let keysignViewModel = KeysignViewModel()
                keysignViewModel.vault = vault
                keysignViewModel.keysignPayload = finalPayload
                keysignViewModel.signatures = result.signatures

                #if DEBUG
                print("[AgentChat] 📡 Calling broadcastTransaction() for \(finalPayload.coin.ticker) on \(finalPayload.coin.chain.name)")
                #endif

                // For UTXO chains (DOGE, BTC, LTC, DASH, ZEC, BCH), broadcastTransaction()
                // uses a completion-handler internally, so the txid isn't set when the
                // async function returns. We wait for the NotificationCenter post instead,
                // with a 30-second timeout.
                let isUTXO = finalPayload.coin.chain.chainType == .UTXO

                if isUTXO {
                    // Start an async waitUntil-style listener before calling broadcast
                    let txid = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                        var token: NSObjectProtocol?
                        var completed = false
                        token = NotificationCenter.default.addObserver(
                            forName: .agentDidBroadcastTx,
                            object: nil,
                            queue: .main
                        ) { notification in
                            guard !completed else { return }
                            completed = true
                            if let t = notification.userInfo?["txid"] as? String {
                                #if DEBUG
                                print("[AgentChat] 📬 NotificationCenter got txid: \(t)")
                                #endif
                                continuation.resume(returning: t)
                            } else {
                                continuation.resume(returning: "")
                            }
                            if let token { NotificationCenter.default.removeObserver(token) }
                        }

                        // Kick off broadcast AFTER registering listener
                        Task { @MainActor in
                            await keysignViewModel.broadcastTransaction()
                            #if DEBUG
                            print("[AgentChat] 📡 broadcastTransaction() returned (UTXO). txid='\(keysignViewModel.txid)' error='\(keysignViewModel.keysignError)'")
                            #endif

                            // If we already have a result (error path or immediate success), resume
                            if !completed {
                                if !keysignViewModel.keysignError.isEmpty {
                                    completed = true
                                    if let token { NotificationCenter.default.removeObserver(token) }
                                    continuation.resume(returning: "")
                                } else {
                                    // Schedule a 30-second timeout
                                    Task {
                                        try? await Task.sleep(for: .seconds(30))
                                        if !completed {
                                            completed = true
                                            #if DEBUG
                                            print("[AgentChat] ⏰ UTXO broadcast timeout — no txid received after 30s")
                                            #endif
                                            if let token { NotificationCenter.default.removeObserver(token) }
                                            continuation.resume(returning: "")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !txid.isEmpty {
                        #if DEBUG
                        print("[AgentChat] ✅ UTXO broadcast success. txid=\(txid)")
                        #endif
                        self.handleTxBroadcasted(txid: txid, vault: vault)
                    } else if !keysignViewModel.keysignError.isEmpty {
                        #if DEBUG
                        print("[AgentChat] ❌ Broadcast error: \(keysignViewModel.keysignError)")
                        #endif
                        throw HelperError.runtimeError(keysignViewModel.keysignError)
                    } else {
                        throw HelperError.runtimeError("Broadcast timed out or returned no txid. Check your balance and network, then try again.")
                    }
                } else {
                    // Non-UTXO chains set txid synchronously inside broadcastTransaction()
                    await keysignViewModel.broadcastTransaction()
                    #if DEBUG
                    print("[AgentChat] 📡 broadcastTransaction() finished — txid='\(keysignViewModel.txid)' keysignError='\(keysignViewModel.keysignError)'")
                    #endif

                    if !keysignViewModel.txid.isEmpty {
                        #if DEBUG
                        print("[AgentChat] ✅ Got txid: \(keysignViewModel.txid)")
                        #endif
                        self.handleTxBroadcasted(txid: keysignViewModel.txid, vault: vault)
                    } else if !keysignViewModel.keysignError.isEmpty {
                        #if DEBUG
                        print("[AgentChat] ❌ Broadcast error from KeysignViewModel: \(keysignViewModel.keysignError)")
                        #endif
                        throw HelperError.runtimeError(keysignViewModel.keysignError)
                    } else {
                        #if DEBUG
                        print("[AgentChat] ❌ Broadcast returned empty txid AND empty keysignError")
                        #endif
                        throw HelperError.runtimeError("Broadcast completed but no txid or error returned. Check your balance and try again.")
                    }
                }
            } catch {
                #if DEBUG
                print("[AgentChat] ❌ executeFastVaultKeysign caught error: \(error)")
                #endif
                #if DEBUG
                print("[AgentChat] ❌ localizedDescription: \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    self.isLoading = false
                    self.appendAssistantMessage("❌ Error: \(error.localizedDescription)")
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func createPendingSendTx(from params: [String: AnyCodable]?, vault: Vault) {
        #if DEBUG
        print("[AgentChat] 🏗️ createPendingSendTx called. params=\(params != nil ? "present" : "nil")")
        #endif
        guard let params = params,
              let chainStr = params["chain"]?.value as? String,
              let symbolStr = params["symbol"]?.value as? String,
              let amountStr = params["amount"]?.value as? String,
              let addressStr = params["address"]?.value as? String else {
            #if DEBUG
            print("[AgentChat] ❌ createPendingSendTx: missing required params. chain=\(params?["chain"]?.value ?? "nil"), symbol=\(params?["symbol"]?.value ?? "nil"), amount=\(params?["amount"]?.value ?? "nil"), address=\(params?["address"]?.value ?? "nil")")
            #endif
            return
        }

        #if DEBUG
        print("[AgentChat] 🏗️ createPendingSendTx: chain=\(chainStr), symbol=\(symbolStr), amount=\(amountStr), to=\(addressStr.prefix(10))...")
        #endif

        // Find coin in vault
        if let coin = vault.coins.first(where: {
            $0.chain.name.lowercased() == chainStr.lowercased() &&
            $0.ticker.lowercased() == symbolStr.lowercased()
        }) {
            let tx = SendTransaction()
            tx.coin = coin
            tx.fromAddress = coin.address
            tx.toAddress = addressStr
            let localizedAmount = amountStr.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
            tx.amount = localizedAmount
            tx.vault = vault // Explicitly assign Vault to allow isFastVault detection

            if let memoStr = params["memo"]?.value as? String {
                tx.memo = memoStr
            }

            self.pendingSendTx = tx
            #if DEBUG
            print("[AgentChat] ✅ createPendingSendTx: SUCCESS — \(coin.ticker) on \(coin.chain.name), from=\(coin.address.prefix(10))..., to=\(addressStr.prefix(10))..., amount=\(amountStr)")
            #endif
        } else {
            #if DEBUG
            print("[AgentChat] ❌ createPendingSendTx: coin NOT FOUND in vault. Looking for chain=\(chainStr), symbol=\(symbolStr). Available coins: \(vault.coins.map { "\($0.chain.name)/\($0.ticker)" }.joined(separator: ", "))")
            #endif
        }
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

    private func primeMCPSession(vault: Vault, token: String, convId: String) async {
        #if DEBUG
        print("[AgentChat] 🔐 Priming backend MCP session with set_vault...")
        #endif
        let setVaultResult = AgentActionResult(
            action: "set_vault",
            success: true,
            data: [
                "ecdsa_public_key": AnyCodable(vault.pubKeyECDSA),
                "eddsa_public_key": AnyCodable(vault.pubKeyEdDSA),
                "chain_code": AnyCodable(vault.hexChainCode)
            ]
        )
        let primeRequest = AgentSendMessageRequest(
            publicKey: vault.pubKeyECDSA,
            model: "anthropic/claude-sonnet-4.5",
            actionResult: setVaultResult
        )
        // Execute without streaming back to UI
        _ = try? await backendClient.sendMessage(convId: convId, request: primeRequest, token: token)
        #if DEBUG
        print("[AgentChat] ✅ MCP session primed")
        #endif
    }

    private func getValidToken(vault: Vault) async -> AgentAuthToken? {
        #if DEBUG
        print("[AgentChat] 🔑 getValidToken: checking cached token for \(vault.pubKeyECDSA.prefix(20))...")
        #endif
        if let token = authService.getCachedToken(vaultPubKey: vault.pubKeyECDSA) {
            #if DEBUG
            print("[AgentChat] 🔑 getValidToken: found cached token, expires \(token.expiresAt)")
            #endif
            return token
        }
        #if DEBUG
        print("[AgentChat] 🔑 getValidToken: no cached token, trying to refresh...")
        #endif
        let refreshed = await authService.refreshIfNeeded(vaultPubKey: vault.pubKeyECDSA)
        #if DEBUG
        print("[AgentChat] 🔑 getValidToken: refresh result = \(refreshed != nil ? "token found" : "nil")")
        #endif
        return refreshed
    }

    private func handleError(_ error: Error) {
        #if DEBUG
        print("[AgentChat] ⚠️ handleError: \(error) — \(error.localizedDescription)")
        #endif
        streamingMessageId = nil
        isLoading = false

        if case AgentBackendClient.AgentBackendError.unauthorized = error {
            #if DEBUG
            print("[AgentChat] ⚠️ handleError: unauthorized, showing password prompt")
            #endif
            passwordRequired = true
            self.error = nil
        } else {
            self.error = error.localizedDescription
        }

        logger.error("Agent error: \(error.localizedDescription)")
    }

    private func formatActionTitle(_ type: String, title: String) -> String {
        switch type {
        case "get_balances": return "FETCHING BALANCES"
        case "get_market_price": return "FETCHING PRICES"
        case "build_swap_tx": return "PREPARING SWAP"
        case "add_token": return "ADDING TOKEN"
        case "add_chain": return "ADDING CHAIN"
        case "get_address_book": return "CHECKING ADDRESS BOOK"
        case "add_address_book": return "UPDATING ADDRESS BOOK"
        default: return title.uppercased()
        }
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
