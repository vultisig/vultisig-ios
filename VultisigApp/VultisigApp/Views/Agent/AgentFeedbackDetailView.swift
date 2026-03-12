//
//  AgentFeedbackDetailView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/03/2026.
//

import SwiftUI

struct AgentFeedbackDetailView: View {
    let category: AgentFeedbackCategory
    let conversationId: String?
    let onSubmit: (String, String) async -> Void

    @State private var details = ""
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(category.title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.turquoise)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.colors.turquoise.opacity(0.1))
                    .cornerRadius(8)

                TextEditor(text: $details)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(Theme.colors.bgSurface1)
                    .cornerRadius(12)
                    .overlay(alignment: .topLeading) {
                        if details.isEmpty {
                            Text("agentFeedbackPlaceholder".localized)
                                .font(Theme.fonts.bodySMedium)
                                .foregroundStyle(Theme.colors.textTertiary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(16)

            Spacer()
        }
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("agentFeedbackTitle".localized)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(Theme.colors.turquoise)
                    } else {
                        Text("agentFeedbackSubmit".localized)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(
                                details.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Theme.colors.textTertiary
                                    : Theme.colors.turquoise
                            )
                    }
                }
                .disabled(details.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
        .onAppear {
            // Focus the text editor
        }
    }

    private func submit() {
        let text = details.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        Task {
            isSubmitting = true
            await onSubmit(category.apiValue, text)
            isSubmitting = false
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        AgentFeedbackDetailView(
            category: .incorrectProposal,
            conversationId: nil
        ) { _, _ in }
    }
}
