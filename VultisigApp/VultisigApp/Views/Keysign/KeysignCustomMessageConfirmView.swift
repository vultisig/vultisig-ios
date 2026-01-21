//
//  KeysignCustomMessageConfirmView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.11.2024.
//

import SwiftUI

struct KeysignCustomMessageConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel

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
                Separator()
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
            Text(NSLocalizedString("message", comment: "") + ":")
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(formattedMessage)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Formats the message for display - decodes hex if needed
    private var formattedMessage: String {
        guard let payload = viewModel.customMessagePayload else { return "" }

        let rawMessage = payload.message

        // For personal_sign, always try to decode hex first (it contains the actual message)
        if payload.method == "personal_sign" && rawMessage.hasPrefix("0x") {
            let hex = String(rawMessage.dropFirst(2))
            if let data = Data(hexString: hex), let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }
        }

        // For other methods, try decoded message from ViewModel
        if let decoded = payload.decodedMessage, !decoded.isEmpty {
            return decoded
        }

        // Try to decode hex to UTF8 (generic fallback)
        if rawMessage.hasPrefix("0x") {
            let hex = String(rawMessage.dropFirst(2))
            if let data = Data(hexString: hex), let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }
        }

        // Fallback to raw message
        return rawMessage
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
