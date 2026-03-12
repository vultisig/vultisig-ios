//
//  AgentChatMessageView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentChatMessageView: View {
    @Environment(\.openURL) var openURL
    let message: AgentChatMessage

    var body: some View {
        if message.toolCall != nil {
            toolCallView
        } else if message.txStatus != nil {
            txStatusView
        } else if message.txProposal != nil {
            txProposalView
        } else {
            messageBubble
        }
    }

    // MARK: - Message Bubble

    private var messageBubble: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if message.role == .user {
                Spacer(minLength: 60)
                messageTimestamp
            }

            if message.role == .assistant {
                AgentOrbView(size: 20, animated: message.isStreaming)
                    .padding(.bottom, 4)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Use verbatim text while streaming to skip Markdown re-parsing on every delta.
                // After the stream finalizes (isStreaming = false), switch to full Markdown.
                if message.isStreaming {
                    Text(verbatim: message.content)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .textSelection(.enabled)
                } else {
                    Text(.init(message.content)) // Renders markdown
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .textSelection(.enabled)
                }

                // Token results
                if let tokens = message.tokenResults, !tokens.isEmpty {
                    tokenResultsView(tokens)
                }
            }
            .padding(12)
            .background(
                message.role == .user
                    ? Theme.colors.turquoise.opacity(0.2)
                    : Theme.colors.bgSurface1
            )
            .cornerRadius(16)

            if message.role == .assistant {
                messageTimestamp
                Spacer(minLength: 60)
            }
        }
    }

    private var messageTimestamp: some View {
        Text(Self.timeFormatter.string(from: message.timestamp))
            .font(Theme.fonts.caption10)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Tool Call Status

    @ViewBuilder
    private var toolCallView: some View {
        if let toolCall = message.toolCall {
            AgentActionStatusView(toolCall: toolCall)
        }
    }

    // MARK: - Transaction Proposal

    @ViewBuilder
    private var txProposalView: some View {
        if let tx = message.txProposal {
            VStack(alignment: .leading, spacing: 12) {

                // Colored status line: icon + type label
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.turquoise)

                    Text("\(tx.txType ?? "SWAP") \(tx.amount) \(tx.fromSymbol) → \(tx.toSymbol ?? "")".uppercased())
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.turquoise)
                }

                // Route detail (indented)
                if let provider = tx.provider {
                    Text(String(format: "agentRoute".localized, provider).uppercased())
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.turquoise)
                        .padding(.leading, 24)
                }

                // Fee detail (indented)
                Text(String(format: "agentEstFee".localized, tx.fromSymbol))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.turquoise)
                    .padding(.leading, 24)

                Text(tx.needsApproval == true ? "agentShouldExecuteSwap".localized : "agentTransactionReady".localized)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .padding(.top, 4)

                // Approval buttons
                HStack(spacing: 12) {
                    Spacer()
                    if tx.needsApproval == true {
                        Button {
                            NotificationCenter.default.post(name: .agentDidRejectTx, object: tx)
                        } label: {
                            Text("no".localized)
                                .font(Theme.fonts.buttonRegularSemibold)
                                .foregroundStyle(Theme.colors.alertError)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Theme.colors.bgSurface1)
                                .cornerRadius(20)
                        }

                        Button {
                            NotificationCenter.default.post(name: .agentDidAcceptTx, object: tx)
                        } label: {
                            Text("yes".localized)
                                .font(Theme.fonts.buttonRegularSemibold)
                                .foregroundStyle(Theme.colors.textPrimary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Theme.colors.bgSurface1)
                                .cornerRadius(20)
                        }
                    } else {
                        Button {
                            NotificationCenter.default.post(name: .agentDidAcceptTx, object: tx)
                        } label: {
                            Text("signTransaction".localized)
                                .font(Theme.fonts.buttonRegularSemibold)
                                .foregroundStyle(Theme.colors.textPrimary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Theme.colors.bgSurface1)
                                .cornerRadius(20)
                        }
                    }
                }
            }
            .padding(16)
            .background(Theme.colors.bgSurface1.opacity(0.3))
            .cornerRadius(16)
        }
    }

    // MARK: - Tx Status

    @ViewBuilder
    private var txStatusView: some View {
        if let txStatus = message.txStatus {
            HStack(spacing: 8) {
                txStatusIcon(for: txStatus.status)

                Text(txStatus.label)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                Spacer()

                if txStatus.status != .pending {
                    Button {
                        openExplorer(txHash: txStatus.txHash, chain: txStatus.chain)
                    } label: {
                        Text("view".localized)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.turquoise)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.colors.bgSurface1.opacity(0.5))
            .cornerRadius(8)
        }
    }

    private func txStatusIcon(for status: AgentTxStatus) -> some View {
        Group {
            switch status {
            case .pending:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            case .confirmed:
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertSuccess)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertError)
            }
        }
    }

    // MARK: - Token Results

    private func tokenResultsView(_ tokens: [AgentTokenSearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tokens, id: \.symbol) { token in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.symbol)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Text(token.name)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }

                    Spacer()

                    if let price = token.priceUsd {
                        Text("$\(price)")
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
                .padding(8)
                .background(Theme.colors.bgPrimary.opacity(0.5))
                .cornerRadius(8)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func openExplorer(txHash: String, chain: String) {
        if let chainEnum = Chain(rawValue: chain) {
            let urlString = Endpoint.getExplorerURL(chain: chainEnum, txid: txHash)
            if let explorerUrl = URL(string: urlString) {
                openURL(explorerUrl)
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AgentChatMessageView(message: AgentChatMessage(
            id: "1", role: .user, content: "What's my ETH balance?", timestamp: Date()
        ))

        AgentChatMessageView(message: AgentChatMessage(
            id: "2", role: .assistant, content: "Your ETH balance is **2.5 ETH** (~$4,500).", timestamp: Date()
        ))

        AgentChatMessageView(message: AgentChatMessage(
            id: "3", role: .assistant, content: "",
            timestamp: Date(),
            toolCall: AgentToolCallInfo(
                actionType: "get_balances", title: "Getting balances",
                status: .running
            )
        ))
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
