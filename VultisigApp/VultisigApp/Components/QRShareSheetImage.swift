//
//  QRShareSheetImage.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

enum QRShareSheetType: String {
    case Keygen = "joinKeygen"
    case Send = "joinSend"
    case Swap = "joinSwap"
    case Address = "address"
}

struct QRShareSheetImage: View {
    let image: Image
    let type: QRShareSheetType

    let vaultName: String

    // Send
    let amount: String
    let toAddress: String

    // Swap
    let fromAmount: String
    let toAmount: String

    // Address
    let address: String

    let padding: CGFloat = 15
    let cornerRadius: CGFloat = 30

    var body: some View {
        content
    }

    var view: some View {
        VStack(spacing: 32) {
            qrCode
            titleContent
            description
            Spacer()
            logo
        }
        .padding(.vertical, 48)
        .font(Theme.fonts.bodyMMedium)
        .foregroundColor(Theme.colors.textPrimary)
        .multilineTextAlignment(.center)
    }

    var titleContent: some View {
        Text(NSLocalizedString(type.rawValue, comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .frame(maxWidth: 200)
            .lineLimit(2)
            .foregroundColor(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
    }

    var description: some View {
        ZStack {
            switch type {
            case .Keygen:
                keygenDescription
            case .Send:
                sendDescription
            case .Swap:
                swapDescription
            case .Address:
                addressDescription
            }
        }
        .padding(.horizontal, 30)
    }

    var keygenDescription: some View {
        Text(NSLocalizedString("previewKeygenDescription", comment: ""))
    }

    var sendDescription: some View {
        VStack(spacing: 10) {
            vaultText
            amountText
            toAddressText
        }
    }

    var swapDescription: some View {
        VStack(spacing: 10) {
            vaultText
            fromAmountText
            toAmountText
        }
    }

    var vaultText: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("vault", comment: "") + ":")
            Text(vaultName)
        }
    }

    var amountText: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("amount", comment: "") + ":")
            Text(amount)
        }
    }

    var toAddressText: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(NSLocalizedString("to", comment: "") + ":")
            Text(toAddress)
        }
    }

    var fromAmountText: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("from", comment: "") + ":")
            Text(fromAmount)
        }
    }

    var toAmountText: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("to", comment: "") + ":")
            Text(toAmount)
        }
    }

    var addressDescription: some View {
        Text(address)
    }
}

#Preview {
    QRShareSheetImage(
        image: Image("VultisigLogo"),
        type: .Keygen,
        vaultName: Vault.example.name,
        amount: "10",
        toAddress: "toAddress",
        fromAmount: "10",
        toAmount: "10",
        address: "addressData"
    )
    .ignoresSafeArea()
    .environmentObject(SettingsViewModel())
}

#if os(iOS)
import SwiftUI

extension QRShareSheetImage {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .frame(width: 375, height: 800)
    }

    var qrCode: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(24)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.colors.border, lineWidth: 2)
            )
            .padding(.horizontal, padding)
    }

    var logo: some View {
        VStack(spacing: 16) {
            Image("VultisigLogo")
                .resizable()
                .frame(width: 110, height: 110)

            Text("vultisig.com")
        }
        .offset(y: -20)
    }
}
#endif

#if os(macOS)
import SwiftUI

extension QRShareSheetImage {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .frame(width: 900, height: 1500)
    }

    var qrCode: some View {
        image
            .resizable()
            .frame(width: 700, height: 700)
            .frame(width: 800, height: 800)
            .background(Theme.colors.bgButtonPrimary.opacity(0.15))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.colors.bgButtonPrimary, style: StrokeStyle(lineWidth: 2, dash: [24]))
            )
            .padding(.horizontal, padding)
            .offset(x: 20, y: 20)
            .padding(.bottom, 50)
    }

    var logo: some View {
        VStack(spacing: 16) {
            Image("VultisigLogo")
                .resizable()
                .frame(width: 110, height: 110)

            Text("vultisig.com")
        }
        .offset(y: -20)
    }
}
#endif
