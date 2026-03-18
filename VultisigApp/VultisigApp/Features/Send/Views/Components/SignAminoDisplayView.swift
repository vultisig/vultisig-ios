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
                    Text("aminoSign".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(Theme.colors.textTertiary)
                    Spacer()
                    Icon(named: "chevron-down", color: Theme.colors.textTertiary, size: 16)
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
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
    }

    private func formatSignAminoData() -> String {
        // Build dictionary with parsed msg.value as JSON objects
        var dict: [String: Any] = [:]

        dict["msgs"] = signAmino.msgs.map { msg -> [String: Any] in
            var msgDict: [String: Any] = ["type": msg.type]
            if let data = msg.value.data(using: .utf8),
               let value = try? JSONSerialization.jsonObject(with: data) {
                msgDict["value"] = value
            } else {
                msgDict["value"] = msg.value
            }
            return msgDict
        }

        var feeDict: [String: Any] = [
            "gas": signAmino.fee.gas,
            "amount": signAmino.fee.amount.map { ["denom": $0.denom, "amount": $0.amount] }
        ]
        if !signAmino.fee.payer.isEmpty { feeDict["payer"] = signAmino.fee.payer }
        if !signAmino.fee.granter.isEmpty { feeDict["granter"] = signAmino.fee.granter }
        if !signAmino.fee.feePayer.isEmpty { feeDict["feePayer"] = signAmino.fee.feePayer }
        dict["fee"] = feeDict

        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{}"
        }

        return jsonString
    }
}
