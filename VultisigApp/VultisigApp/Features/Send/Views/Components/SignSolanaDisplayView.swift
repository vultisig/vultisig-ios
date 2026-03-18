//
//  SignSolanaDisplayView.swift
//  VultisigApp
//
//  Component to display Solana raw transaction data
//

import SwiftUI

struct SignSolanaDisplayView: View {
    let signSolana: SignSolana

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text("Solana Raw Transaction")
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
                        // Parse and display all instructions from all transactions
                        instructionsSummarySection()

                        // Raw transaction data
                        rawTransactionsSection()
                    }
                    .padding(16)
                }
                .frame(maxHeight: 400)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
    }

    private func instructionsSummarySection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Parse all instructions from all transactions
            let allInstructions = signSolana.rawTransactions.flatMap { tx -> [ParsedSolanaTransaction.ParsedInstruction] in
                guard let parsed = try? SolanaTransactionParser.parse(base64Transaction: tx) else {
                    return []
                }
                return parsed.instructions
            }

            if !allInstructions.isEmpty {
                Text("Transaction Instructions Summary")
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(allInstructions.enumerated()), id: \.offset) { idx, instruction in
                        instructionRow(instruction: instruction, index: idx)
                    }
                }
            }
        }
    }

    private func rawTransactionsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Raw Transaction Data")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text(signSolana.rawTransactions.joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.colors.turquoise)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgPrimary)
            .cornerRadius(8)
        }
    }

    private func instructionRow(instruction: ParsedSolanaTransaction.ParsedInstruction, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Instruction title: index + type (if available)
            HStack {
                Text("Instruction \(index + 1)")
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                if let instructionType = instruction.instructionType {
                    Text(": \(instructionType)")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }

            // Program ID
            Text("Program ID: \(instruction.programId)")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            // Accounts and data length
            Text("Accounts: \(instruction.accountsCount) | Data length: \(instruction.dataLength) bytes")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.colors.bgPrimary)
        .cornerRadius(8)
    }

}
