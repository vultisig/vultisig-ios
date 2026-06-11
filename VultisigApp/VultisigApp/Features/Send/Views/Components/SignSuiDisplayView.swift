//
//  SignSuiDisplayView.swift
//  VultisigApp
//
//  Renders the decoded Sui Programmable Transaction Block (PTB) carried by a
//  `signSui` keysign payload on the verify / join screens, so co-signers see
//  the actual transaction instead of an empty "0 SUI" send card.
//

import SwiftUI

struct SignSuiDisplayView: View {
    let signSui: SignSui

    @State private var isExpanded: Bool = false

    private var summary: SuiTransactionDataSummary? {
        SuiTransactionDataParser.parse(base64TransactionData: signSui.unsignedTxMsg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text("suiTransaction".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Icon(named: "chevron-down", color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let summary {
                            decodedSection(summary)
                        }
                        rawBytesSection
                    }
                    .padding(16)
                }
                .frame(maxHeight: 400)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
    }

    private func decodedSection(_ summary: SuiTransactionDataSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row(title: "sender".localized, value: summary.sender)
            row(title: "gasOwner".localized, value: summary.gasOwner)
            row(title: "gasBudget".localized, value: String(summary.gasBudget))
            row(title: "gasPrice".localized, value: String(summary.gasPrice))
            row(title: "commands".localized, value: String(summary.commandCount))
            row(title: "inputs".localized, value: String(summary.inputCount))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rawBytesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("transactionBytes".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Text(signSui.unsignedTxMsg)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.colors.turquoise)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.colors.bgPrimary)
                .cornerRadius(8)
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
