//
//  KeysignApproveConfirmView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 20.05.2024.
//

import SwiftUI

struct KeysignApproveConfirmView: View {

    @ObservedObject var viewModel: JoinKeysignViewModel

    var body: some View {
        VStack {
            fields
            button
        }
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                summary
            }
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            getValueCell(for: "Action", with: getAction())
            Separator()
            getValueCell(for: "Spender", with: getSpender())
            Separator()
            getValueCell(for: "Amount", with: getAmount())
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }

    var button: some View {
        Button(action: {
            self.viewModel.joinKeysignCommittee()
        }) {
            FilledButton(title: "joinKeySign")
        }
        .padding(20)
    }

    func getAction() -> String {
        return NSLocalizedString("Approve", comment: "")
    }

    func getSpender() -> String {
        return viewModel.keysignPayload?.approvePayload?.spender ?? .empty
    }

    func getAmount() -> String {
        return "UNLIMITED"
    }

    func getValueCell(for title: String, with value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)

            Text(value)
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
