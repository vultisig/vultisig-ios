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

        // Extract memo from TxBody
        let memo = CosmosSignDirectParser.extractMemo(from: bodyData)

        // Extract fee from AuthInfo
        let feeInfo = CosmosSignDirectParser.extractFee(from: authInfoData)

        // Build display struct
        let display = SignDirectDisplayData(
            chainId: signDirect.chainID,
            accountNumber: signDirect.accountNumber,
            memo: memo,
            fee: feeInfo.map { info in
                SignDirectFeeDisplay(
                    gasLimit: String(info.gasLimit),
                    amount: info.amounts.map { CoinDisplay(denom: $0.denom, amount: $0.amount) }
                )
            },
            bodyBytes: signDirect.bodyBytes.count > 100
                ? String(signDirect.bodyBytes.prefix(100)) + "..."
                : signDirect.bodyBytes,
            authInfoBytes: signDirect.authInfoBytes.count > 100
                ? String(signDirect.authInfoBytes.prefix(100)) + "..."
                : signDirect.authInfoBytes
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(display),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        return jsonString
    }
}

// MARK: - Display Models
private struct SignDirectDisplayData: Codable {
    let chainId: String
    let accountNumber: String
    let memo: String?
    let fee: SignDirectFeeDisplay?
    let bodyBytes: String
    let authInfoBytes: String
}

private struct SignDirectFeeDisplay: Codable {
    let gasLimit: String
    let amount: [CoinDisplay]
}

private struct CoinDisplay: Codable {
    let denom: String
    let amount: String
}
