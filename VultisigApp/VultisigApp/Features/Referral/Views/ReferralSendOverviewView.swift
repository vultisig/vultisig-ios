//
//  ReferralSendOverviewView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-28.
//

import SwiftUI

struct ReferralSendOverviewView: View {
    @ObservedObject var sendTx: SendTransaction

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            summary
            Spacer()
        }
        .padding(24)
    }

    var summary: some View {
        VStack(alignment: .leading, spacing: 24) {
            title
            assetDetail
            overview
        }
        .padding(24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
    }

    var title: some View {
        Text(NSLocalizedString("youreSending", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textSecondary)
    }

    var assetDetail: some View {
        HStack {
            Image("rune")
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(32)

            Text("\(sendTx.amount)")
                .foregroundColor(Theme.colors.textPrimary)

            Text("RUNE")
                .foregroundColor(Theme.colors.textSecondary)

            Spacer()
        }
        .font(Theme.fonts.bodyLMedium)
    }

    var separator: some View {
        Separator()
    }

    var overview: some View {
        VStack(spacing: 12) {
            separator

            getCell(
                title: "from",
                description: sendTx.vault?.name ?? "",
                bracketValue: getVaultAddress()
            )

            separator

            getCell(
                title: "network",
                description: "THORChain",
                icon: "rune"
            )

            separator

            getCell(
                title: "gas",
                description: "\(sendTx.gasInReadable)"
            )

            separator

            getCell(
                title: "memo",
                description: sendTx.memo,
                isForMemo: true
            )
        }
    }

    private func getCell(title: String, description: String, bracketValue: String? = nil, icon: String? = nil, isForMemo: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if let icon {
                Image(icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(16)
            }

            Text(description)
                .foregroundColor(isForMemo ? Theme.colors.textTertiary : Theme.colors.textPrimary)
                .lineLimit(isForMemo ? 2 : 1)
                .truncationMode(.tail)

            if let bracketValue {
                Text("(\(bracketValue))")
                    .foregroundColor(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(Theme.fonts.bodySMedium)
    }

    private func getVaultAddress() -> String? {
        guard let nativeCoin = sendTx.vault?.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) else {
            return nil
        }

        return nativeCoin.address
    }
}

#Preview {
    ReferralSendOverviewView(
        sendTx: SendTransaction(),
    )
    .environmentObject(HomeViewModel())
}
