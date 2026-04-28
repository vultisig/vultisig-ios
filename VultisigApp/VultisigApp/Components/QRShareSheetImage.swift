//
//  QRShareSheetImage.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

enum QRShareSheetType {
    case Keygen
    case Send
    case Swap
    case Address
}

struct QRShareSheetImage: View {
    let image: Image
    let type: QRShareSheetType

    let vaultName: String

    // Send (Keysign)
    let amount: String
    let toAddress: String
    let coinLogo: String

    // Swap
    let fromAmount: String
    let toAmount: String

    // Keygen
    let vaultType: String

    // Address
    let address: String

    var body: some View {
        content
    }

    var view: some View {
        VStack(spacing: 16) {
            qrCard
            metadataCard
            signature
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var qrCard: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(qrInnerPadding)
            .background(Theme.colors.bgSurface1)
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
    }

    var metadataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            metadataRows
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.colors.bgSurface1)
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
    }

    @ViewBuilder
    var metadataRows: some View {
        switch type {
        case .Send:
            VStack(spacing: 14) {
                metadataRow(label: "vault".localized) {
                    Text(vaultName)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                separator
                metadataRow(label: "amount".localized) {
                    HStack(spacing: 4) {
                        if !coinLogo.isEmpty {
                            AsyncImageView(
                                logo: coinLogo,
                                size: CGSize(width: 16, height: 16),
                                ticker: "",
                                tokenChainLogo: nil
                            )
                            .frame(width: 16, height: 16)
                        }
                        Text(amount)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
                separator
                metadataRow(label: "to".localized) {
                    Text(toAddress.truncatedAddress)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
        case .Keygen:
            VStack(spacing: 14) {
                metadataRow(label: "vault".localized) {
                    Text(vaultName)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                if !vaultType.isEmpty {
                    separator
                    metadataRow(label: "shareQRType".localized) {
                        Text(vaultType)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
        case .Swap:
            VStack(spacing: 14) {
                metadataRow(label: "vault".localized) {
                    Text(vaultName)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                separator
                metadataRow(label: "from".localized) {
                    Text(fromAmount)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                separator
                metadataRow(label: "to".localized) {
                    Text(toAmount)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
        case .Address:
            Text(address)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func metadataRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer(minLength: 16)
            trailing()
        }
    }

    var separator: some View {
        Rectangle()
            .fill(Theme.colors.borderLight)
            .frame(height: 1)
    }

    var signature: some View {
        VStack(spacing: 8) {
            Image("vultisig-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 33, height: 33)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("Vultisig")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    var title: String {
        switch type {
        case .Keygen:
            return "joinKeygen".localized
        case .Send:
            return "joinKeysign".localized
        case .Swap:
            return "joinSwap".localized
        case .Address:
            return "address".localized
        }
    }
}

private extension QRShareSheetImage {
    var cardCornerRadius: CGFloat { 24 }
    var qrInnerPadding: CGFloat { 16 }
}

#Preview {
    QRShareSheetImage(
        image: Image("vultisig-logo"),
        type: .Send,
        vaultName: Vault.example.name,
        amount: "100 USDC",
        toAddress: "0xe3F8345678901234567890123456CE1e8b2",
        coinLogo: "usdc",
        fromAmount: "10",
        toAmount: "10",
        vaultType: "2-of-3",
        address: "addressData"
    )
    .ignoresSafeArea()
    .environmentObject(SettingsViewModel())
}

#if os(iOS)
extension QRShareSheetImage {
    var content: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            view
        }
        .frame(width: 375, height: 720)
    }
}
#endif

#if os(macOS)
extension QRShareSheetImage {
    var content: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            view
        }
        .frame(width: 900, height: 1500)
    }
}
#endif
