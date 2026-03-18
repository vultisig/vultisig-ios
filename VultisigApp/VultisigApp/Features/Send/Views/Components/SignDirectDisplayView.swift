//
//  SignDirectDisplayView.swift
//  VultisigApp
//
//  Component to display Cosmos SignDirect transaction data as formatted JSON
//

import SwiftUI

struct SignDirectDisplayView: View {
    let signDirect: SignDirect

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
                        if let decodedData = decodeSignDirectData() {
                            Text(decodedData)
                        } else {
                            Text("Unable to decode transaction data")
                        }
                    }
                    .font(Theme.fonts.bodySRegular)
                    .foregroundColor(Theme.colors.textPrimary)
                    .padding(16)
                }
                .frame(maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
    }

    private func decodeSignDirectData() -> String? {
        guard let bodyData = Data(base64Encoded: signDirect.bodyBytes),
              let authInfoData = Data(base64Encoded: signDirect.authInfoBytes) else {
            return nil
        }

        // Extract data from protobuf
        let memo = CosmosSignDirectParser.extractMemo(from: bodyData) ?? ""
        let messages = CosmosSignDirectParser.extractMessages(from: bodyData)
        let feeInfo = CosmosSignDirectParser.extractFee(from: authInfoData)
        let sequence = CosmosSignDirectParser.extractSequence(from: authInfoData) ?? 0

        // Build dictionary
        var dict: [String: Any] = [
            "chainId": signDirect.chainID,
            "accountNumber": signDirect.accountNumber,
            "sequence": String(sequence),
            "memo": memo
        ]

        // Add messages
        dict["messages"] = messages.map { msg -> [String: Any] in
            ["typeUrl": msg.typeUrl, "value": msg.value]
        }

        // Add fee
        if let fee = feeInfo {
            dict["fee"] = [
                "amount": fee.amounts.map { ["denom": $0.denom, "amount": $0.amount] },
                "gasLimit": String(fee.gasLimit)
            ]
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        return jsonString
    }
}
