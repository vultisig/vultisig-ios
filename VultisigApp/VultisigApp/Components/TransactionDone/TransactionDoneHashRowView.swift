//
//  TransactionDoneHashRowView.swift
//  VultisigApp
//
//  Tx-hash row used by every "done" surface (Send / Swap / QBTC /
//  cosigner). Renders the truncated hash, the optional copy button,
//  and the explorer-link button.
//

import SwiftUI

struct TransactionDoneHashRowView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.notifyHashCopied) var notifyHashCopied

    let hash: String
    let explorerLink: String
    let showCopy: Bool

    var body: some View {
        HStack(spacing: 32) {
            Text(NSLocalizedString("transactionHash", comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            HStack(spacing: 8) {
                if showCopy {
                    hashWithCopyView
                } else {
                    hashView
                }

                explorerLinkView
            }
        }
        .font(Theme.fonts.bodySMedium)
    }

    var explorerLinkView: some View {
        Button {
            if let url = URL(string: explorerLink) {
                openURL(url)
            }
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    var hashWithCopyView: some View {
        Button {
            copyHash()
        } label: {
            HStack(spacing: 2) {
                hashView
                Image(systemName: "doc.on.clipboard")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
        }
    }

    var hashView: some View {
        Text(hash)
            .foregroundStyle(Theme.colors.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    func copyHash() {
        notifyHashCopied()
        ClipboardManager.copyToClipboard(explorerLink)
    }
}

#Preview {
    TransactionDoneHashRowView(
        hash: "294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        explorerLink: "https://thorchain.net/tx/294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        showCopy: true
    )
}
