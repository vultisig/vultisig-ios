//
//  KeysignCustomMessageConfirmView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.11.2024.
//

import SwiftUI

struct KeysignCustomMessageConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    @State private var isMessageExpanded: Bool = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                title
                summary
                button
            }
            .foregroundColor(Theme.colors.textPrimary)
        }
    }

    var title: some View {
        Text(NSLocalizedString("verify", comment: ""))
            .frame(maxWidth: .infinity, alignment: .center)
            .font(Theme.fonts.bodyLMedium)
    }

    var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                method
                Separator()
                message
            }
            .padding(16)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(10)
            .padding(16)
        }
    }

    var method: some View {
        getPrimaryCell(title: "Method", value: viewModel.customMessagePayload?.method ?? "")
    }

    var message: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isMessageExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text(NSLocalizedString("message", comment: "") + ":")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(Theme.colors.textTertiary)
                    Spacer()
                    Icon(named: "chevron-down", color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isMessageExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isMessageExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(formattedMessage)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundColor(Theme.colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Formats the message for display - decodes hex if needed
    private var formattedMessage: String {
        guard let payload = viewModel.customMessagePayload else { return "" }

        if let decoded = payload.decodedMessage, !decoded.isEmpty {
            return decoded
        }

        // Fallback: try hex to UTF-8
        if payload.message.hasPrefix("0x") {
            let hex = String(payload.message.dropFirst(2))
            if let data = Data(hexString: hex), let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }
        }

        return payload.message
    }

    var button: some View {
        PrimaryButton(title: "joinKeysign") {
            viewModel.joinKeysignCommittee()
        }
        .padding(20)
    }

    private func getPrimaryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString(title, comment: "") + ":")
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textTertiary)
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getSummaryCell(title: String, value: String) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: "") + ":")
            Spacer()
            Text(value)
        }
        .font(Theme.fonts.bodyMMedium)
        .foregroundColor(Theme.colors.textPrimary)
    }
}
