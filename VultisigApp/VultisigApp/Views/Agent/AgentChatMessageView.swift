//
//  AgentChatMessageView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentChatMessageView: View {
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
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(.init(message.content)) // Renders markdown
                    .font(.body)
                    .foregroundColor(Theme.colors.textPrimary)
                    .textSelection(.enabled)

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

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    // MARK: - Tool Call Status

    @ViewBuilder
    private var toolCallView: some View {
        if let toolCall = message.toolCall {
            HStack(spacing: 8) {
                statusIcon(for: toolCall.status)

                Text(toolCall.title)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(Theme.colors.textTertiary)

                Spacer()

                if let error = toolCall.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(Theme.colors.alertError)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func statusIcon(for status: AgentToolCallStatus) -> some View {
        Group {
            switch status {
            case .running:
                Image(systemName: "sun.max") // Figma uses a sun/spinner
                    .font(.caption)
                    .foregroundColor(Theme.colors.textTertiary)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.colors.alertSuccess)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.colors.alertError)
            }
        }
    }
    
    // MARK: - Transaction Proposal
    
    @ViewBuilder
    private var txProposalView: some View {
        if let tx = message.txProposal {
            VStack(alignment: .leading, spacing: 12) {
                
                // Route header
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.footnote)
                        .foregroundColor(Theme.colors.textTertiary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(tx.txType ?? "SWAP") \(tx.amount) \(tx.fromSymbol) → \(tx.toSymbol ?? "")")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Theme.colors.textTertiary)
                        
                        if let provider = tx.provider {
                            Text("ROUTE: \(provider)".uppercased())
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(Theme.colors.textTertiary)
                        }
                        
                        // Using a dummy fee since it's not strictly typed in the payload yet
                        Text("EST. FEE: 0.001 \(tx.fromSymbol)")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Theme.colors.textTertiary)
                    }
                }
                .padding(.bottom, 8)
                
                Text(tx.needsApproval == true ? "Should I execute the swap?" : "Transaction ready to sign.")
                    .font(.body)
                    .foregroundColor(Theme.colors.textPrimary)
                
                HStack(spacing: 12) {
                    Spacer()
                    if tx.needsApproval == true {
                        Button {
                            // Action handled by ViewModel via Notifications or a completion block.
                            // To keep View clean, we post a Notification
                            NotificationCenter.default.post(name: .agentDidRejectTx, object: tx)
                        } label: {
                            Text("No")
                                .font(.body.bold())
                                .foregroundColor(Theme.colors.textPrimary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Theme.colors.bgSurface1)
                                .cornerRadius(20)
                        }
                        
                        Button {
                            NotificationCenter.default.post(name: .agentDidAcceptTx, object: tx)
                        } label: {
                            Text("Yes")
                                .font(.body.bold())
                                .foregroundColor(Theme.colors.bgPrimary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Theme.colors.turquoise)
                                .cornerRadius(20)
                        }
                    } else {
                        Button {
                            NotificationCenter.default.post(name: .agentDidAcceptTx, object: tx)
                        } label: {
                            Text("Sign Transaction")
                                .font(.body.bold())
                                .foregroundColor(Theme.colors.bgPrimary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Theme.colors.turquoise)
                                .cornerRadius(20)
                        }
                    }
                }
            }
            .padding(16)
            .background(Theme.colors.bgSurface1.opacity(0.3)) // Slight tint
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
                    .font(.footnote)
                    .foregroundColor(Theme.colors.textPrimary)

                Spacer()

                if txStatus.status != .pending {
                    Button {
                        openExplorer(txHash: txStatus.txHash, chain: txStatus.chain)
                    } label: {
                        Text("View")
                            .font(.caption)
                            .foregroundColor(Theme.colors.turquoise)
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
                    .font(.caption)
                    .foregroundColor(Theme.colors.alertSuccess)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.colors.alertError)
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
                            .font(.footnote.bold())
                            .foregroundColor(Theme.colors.textPrimary)
                        Text(token.name)
                            .font(.caption)
                            .foregroundColor(Theme.colors.textTertiary)
                    }

                    Spacer()

                    if let price = token.priceUsd {
                        Text("$\(price)")
                            .font(.footnote)
                            .foregroundColor(Theme.colors.textPrimary)
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
            let url = Endpoint.getExplorerURL(chain: chainEnum, txid: txHash)
            if let explorerUrl = URL(string: url) {
                #if os(iOS)
                UIApplication.shared.open(explorerUrl)
                #elseif os(macOS)
                NSWorkspace.shared.open(explorerUrl)
                #endif
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
