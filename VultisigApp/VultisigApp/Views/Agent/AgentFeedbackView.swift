//
//  AgentFeedbackView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/03/2026.
//

import SwiftUI

struct AgentFeedbackView: View {
    let conversationId: String?
    let onSubmit: (String, String) async -> Void

    @State private var selectedCategory: AgentFeedbackCategory?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("agentFeedbackTitle".localized)
                        .font(Theme.fonts.title3)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text("agentFeedbackSubtitle".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 24)
                .padding(.bottom, 16)

                Separator(color: Theme.colors.borderLight, opacity: 1)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(AgentFeedbackCategory.allCases) { category in
                            NavigationLink(value: category) {
                                feedbackRow(category)
                            }
                        }
                    }
                }
            }
            .background(Theme.colors.bgPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .frame(width: 28, height: 28)
                            .background(Theme.colors.bgSurface1)
                            .clipShape(Circle())
                    }
                }
            }
            .navigationDestination(for: AgentFeedbackCategory.self) { category in
                AgentFeedbackDetailView(
                    category: category,
                    conversationId: conversationId,
                    onSubmit: onSubmit
                )
            }
        }
    }

    private func feedbackRow(_ category: AgentFeedbackCategory) -> some View {
        HStack {
            Text(category.title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Theme.colors.bgPrimary)
    }
}

enum AgentFeedbackCategory: String, CaseIterable, Identifiable, Hashable {
    case incorrectProposal
    case wrongExecution
    case tooSlow
    case uiConfusing
    case failedTransaction
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incorrectProposal: return "agentFeedbackIncorrectProposal".localized
        case .wrongExecution: return "agentFeedbackWrongExecution".localized
        case .tooSlow: return "agentFeedbackTooSlow".localized
        case .uiConfusing: return "agentFeedbackUiConfusing".localized
        case .failedTransaction: return "agentFeedbackFailedTransaction".localized
        case .other: return "agentFeedbackOther".localized
        }
    }

    var apiValue: String { rawValue }
}

#Preview {
    AgentFeedbackView(conversationId: nil) { _, _ in }
}
