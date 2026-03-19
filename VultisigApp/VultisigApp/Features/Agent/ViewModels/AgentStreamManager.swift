//
//  AgentStreamManager.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-03-11.
//

import Foundation
import OSLog
import SwiftUI

@MainActor
final class AgentStreamManager: AgentLogging {
    private weak var viewModel: AgentChatViewModel?

    // SSE delta buffering — accumulate characters and flush at ~25 Hz
    private var streamingBuffer: String = ""
    private var flushTimer: Timer?
    var streamingMessageId: String?

    let logger = Logger(subsystem: "com.vultisig", category: "AgentStreamManager")

    init(viewModel: AgentChatViewModel) {
        self.viewModel = viewModel
    }

    func reset() {
        stopFlushTimer()
        streamingBuffer = ""
        streamingMessageId = nil
    }

    func cancel() {
        reset()
    }

    func setStreamingMessageId(_ id: String?) {
        reset()
        streamingMessageId = id
    }

    func discardPendingStreamingSeedMessage() {
        guard let streamId = streamingMessageId,
              let viewModel = viewModel,
              let idx = viewModel.messages.firstIndex(where: { $0.id == streamId }),
              viewModel.messages[idx].content.isEmpty,
              viewModel.messages[idx].isStreaming else {
            reset()
            return
        }

        viewModel.messages.remove(at: idx)
        reset()
    }

    func handleSSEEvent(_ event: AgentSSEEvent, vault: Vault?) {
        guard let viewModel = viewModel else { return }

        switch event {
        case .textDelta(let delta):
            handleTextDelta(delta)

        case .title(let title):
            viewModel.conversationTitle = title

        case .actions(let actions):
            guard let v = vault else {
                warningLog("[AgentChat] Skipping actions: no bound vault for this stream")
                break
            }
            viewModel.handleActions(actions, vault: v)

        case .suggestions:
            // Suggestions are displayed in the conversation starters, not inline
            break

        case .txReady(let txReady):
            viewModel.handleTxReady(txReady)

        case .tokens(let tokenResults):
            // Attach token results to the current streaming message
            if let streamId = streamingMessageId,
               let idx = viewModel.messages.firstIndex(where: { $0.id == streamId }) {
                viewModel.messages[idx].tokenResults = tokenResults
            }

        case .message(let backendMsg):
            finalizeStreamingMessage(with: backendMsg)

        case .error(let errorMsg):
            let streamId = streamingMessageId
            // Mark the in-flight message as finished so it renders Markdown
            if let streamId,
               let idx = viewModel.messages.firstIndex(where: { $0.id == streamId }) {
                viewModel.messages[idx].isStreaming = false
            }
            reset()
            let normalized = viewModel.normalizeErrorMessage(errorMsg)
            if normalized == "agent stopped" {
                viewModel.appendAssistantMessage("agentStopped".localized)
            } else {
                viewModel.error = normalized
            }
            viewModel.isLoading = false

        case .done:
            let streamId = streamingMessageId
            let bufferedText = streamingBuffer
            if !bufferedText.isEmpty,
               let streamId,
               let idx = viewModel.messages.firstIndex(where: { $0.id == streamId }) {
                viewModel.messages[idx].content = bufferedText
                viewModel.messages[idx].isStreaming = false
            } else if let streamId,
                      let idx = viewModel.messages.firstIndex(where: { $0.id == streamId }) {
                viewModel.messages[idx].isStreaming = false
            }
            reset()
            viewModel.isLoading = false
        }
    }

    private func handleTextDelta(_ delta: String) {
        guard let viewModel = viewModel else { return }

        streamingBuffer += delta

        if streamingMessageId == nil {
            // No pre-seeded message: create one and start streaming
            let msgId = "streaming-\(Date().timeIntervalSince1970)"
            streamingMessageId = msgId
            debugLog("[AgentChat] Created new streaming message id: \(msgId)")
            let streamMsg = AgentChatMessage(
                id: msgId,
                role: .assistant,
                content: "",
                timestamp: Date(),
                isStreaming: true
            )
            viewModel.messages.append(streamMsg)
            viewModel.isLoading = false
        } else if let streamId = streamingMessageId,
                  let idx = viewModel.messages.firstIndex(where: { $0.id == streamId }),
                  !viewModel.messages[idx].isStreaming {
            // Bug fix: pre-seeded seed message (from auto-execute) was not marked isStreaming.
            // Mark it now so the view switches to plain-text mode immediately.
            viewModel.messages[idx].isStreaming = true
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
              let viewModel = viewModel,
              let streamId = streamingMessageId,
              let idx = viewModel.messages.firstIndex(where: { $0.id == streamId }) else { return }
        viewModel.messages[idx].content = streamingBuffer
    }

    private func finalizeStreamingMessage(with backendMsg: AgentBackendMessage) {
        guard let viewModel = viewModel else { return }
        debugLog("[AgentChat] Finalizing streaming message id: \(backendMsg.id)")
        let streamId = streamingMessageId

        // Backend echoes tool action results as conversation messages (e.g.
        // "[Action result: Refresh Balances succeeded — data: {...}]").
        // These are useful for history but should NOT appear as visible
        // bubbles during live streaming — they render as ugly JSON blobs.
        let isActionResultEcho = backendMsg.content.hasPrefix("[Action result:")

        if let streamId,
           let idx = viewModel.messages.firstIndex(where: { $0.id == streamId }) {
            if isActionResultEcho {
                // Discard the seed message entirely — it was only a placeholder
                viewModel.messages.remove(at: idx)
            } else {
                let oldMsg = viewModel.messages[idx]
                // isStreaming = false → view will now render full Markdown
                viewModel.messages[idx] = AgentChatMessage(
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
            }
        } else if !isActionResultEcho,
                  !backendMsg.content.trimmingCharacters(in: .whitespaces).isEmpty {
            let msg = AgentChatMessage(
                id: backendMsg.id,
                role: .assistant,
                content: backendMsg.content,
                timestamp: AgentBackendClient.parseISO8601(backendMsg.createdAt) ?? Date()
            )
            viewModel.messages.append(msg)
        }
        reset()
        viewModel.isLoading = false
    }
}
