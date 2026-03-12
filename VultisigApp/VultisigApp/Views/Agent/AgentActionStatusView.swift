//
//  AgentActionStatusView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2026-03-12.
//

import SwiftUI

struct AgentActionStatusView: View {
    let toolCall: AgentToolCallInfo

    private var category: AgentActionCategory {
        switch toolCall.status {
        case .error:
            return .error
        case .success:
            let derived = AgentActionCategory.from(actionType: toolCall.actionType)
            return derived == .analyzing ? .success : derived
        case .running:
            return AgentActionCategory.from(actionType: toolCall.actionType)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            actionIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(toolCall.title.uppercased())
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(colorForCategory)

                if let error = toolCall.error {
                    Text(error)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.alertError)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Icon

    @ViewBuilder
    private var actionIcon: some View {
        if toolCall.status == .running {
            Image(systemName: category.iconName)
                .font(Theme.fonts.caption12)
                .foregroundStyle(colorForCategory)
                .symbolEffect(.pulse, isActive: true)
        } else {
            Image(systemName: category.iconName)
                .font(Theme.fonts.caption12)
                .foregroundStyle(colorForCategory)
        }
    }

    // MARK: - Color

    private var colorForCategory: Color {
        resolveColor(category.color)
    }

    private func resolveColor(_ actionColor: AgentActionColor) -> Color {
        switch actionColor {
        case .muted:   return Theme.colors.textTertiary
        case .teal:    return Theme.colors.turquoise
        case .blue:    return Theme.colors.alertInfo
        case .green:   return Theme.colors.alertSuccess
        case .red:     return Theme.colors.alertError
        case .neutral: return Theme.colors.textSecondary
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AgentActionStatusView(toolCall: AgentToolCallInfo(
            actionType: "analyze_route", title: "Analyzing route",
            status: .running
        ))
        AgentActionStatusView(toolCall: AgentToolCallInfo(
            actionType: "swap_completed", title: "Swap completed",
            status: .success
        ))
        AgentActionStatusView(toolCall: AgentToolCallInfo(
            actionType: "execution_failed", title: "Execution failed",
            status: .error, error: "Insufficient funds"
        ))
        AgentActionStatusView(toolCall: AgentToolCallInfo(
            actionType: "get_balances", title: "Balance update",
            status: .success
        ))
        AgentActionStatusView(toolCall: AgentToolCallInfo(
            actionType: "approve_swap", title: "Approve 1000 USDT",
            status: .running
        ))
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
