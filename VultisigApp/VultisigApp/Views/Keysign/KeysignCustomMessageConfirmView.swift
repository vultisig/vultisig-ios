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
            .background(Theme.colors.bgSecondary)
            .cornerRadius(10)
            .padding(16)
        }
    }

    var method: some View {
        getPrimaryCell(title: "Method", value: viewModel.customMessagePayload?.method ?? "")
    }

    var message: some View {
        // Show decoded message if available, otherwise show raw message
        if let decodedMessage = viewModel.customMessagePayload?.decodedMessage, !decodedMessage.isEmpty {
            getPrimaryCell(title: "Transaction Details", value: decodedMessage)
        } else {
            getPrimaryCell(title: "Message", value: viewModel.customMessagePayload?.message ?? "")
        }
    }

    var button: some View {
        PrimaryButton(title: "joinKeySign") {
            viewModel.joinKeysignCommittee()
        }
        .padding(20)
    }

    private func getPrimaryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString(title, comment: "") + ":")
                .font(Theme.fonts.bodyLMedium)
                .foregroundColor(Theme.colors.textPrimary)
            Text(value)
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.bgButtonPrimary)
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
