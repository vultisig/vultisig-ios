//
//  SignAminoDisplayView.swift
//  VultisigApp
//
//  Component to display Cosmos SignAmino transaction data as formatted JSON
//

import SwiftUI

struct SignAminoDisplayView: View {
    let signAmino: SignAmino

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text("directSign".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(Theme.colors.textExtraLight)
                    Spacer()
                    Icon(named: "chevron-down", color: Theme.colors.textExtraLight, size: 16)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(formatSignAminoData())
                            .font(Theme.fonts.bodySRegular)
                            .foregroundColor(Theme.colors.textPrimary)
                            .padding(16)
                    }
                }
                .frame(maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgTertiary))
            }
        }
    }

    private func formatSignAminoData() -> String {
        // Build display struct
        let display = SignAminoDisplayData(
            msgs: signAmino.msgs.map { msg in
                MessageDisplay(
                    type: msg.type,
                    value: msg.value
                )
            },
            fee: SignAminoFeeDisplay(
                gas: signAmino.fee.gas,
                amount: signAmino.fee.amount.map { coin in
                    CoinDisplay(denom: coin.denom, amount: coin.amount)
                },
                payer: signAmino.fee.payer.isEmpty ? nil : signAmino.fee.payer,
                granter: signAmino.fee.granter.isEmpty ? nil : signAmino.fee.granter,
                feePayer: signAmino.fee.feePayer.isEmpty ? nil : signAmino.fee.feePayer
            )
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(display),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{}"
        }

        return jsonString
    }
}

// MARK: - Display Models
private struct SignAminoDisplayData: Codable {
    let msgs: [MessageDisplay]
    let fee: SignAminoFeeDisplay
}

private struct MessageDisplay: Codable {
    let type: String
    let value: String
}

private struct SignAminoFeeDisplay: Codable {
    let gas: String
    let amount: [CoinDisplay]
    let payer: String?
    let granter: String?
    let feePayer: String?
}

private struct CoinDisplay: Codable {
    let denom: String
    let amount: String
}
