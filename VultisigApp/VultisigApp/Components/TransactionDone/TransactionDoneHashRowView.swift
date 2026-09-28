//
//  TransactionDoneHashRowView.swift
//  VultisigApp
//
//  Tx-hash row used by every "done" surface (Send / Swap approval+main
//  hash / QBTC / cosigner) — one shared component, mirroring Android's
//  `TxDetails`. Renders the truncated hash, the optional copy button,
//  and the explorer-link button.
//
//  The explorer button is hidden whenever `explorerLink` is empty
//  (e.g. a chain with no mapped explorer) rather than rendering a dead
//  button, and the copy action falls back to the raw hash in that
//  case instead of copying nothing — same rule Android's `TxDetails`
//  applies.
//

import SwiftUI

struct TransactionDoneHashRowView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.notifyHashCopied) var notifyHashCopied

    /// Localization key for the row's leading label. Defaults to the
    /// Send Done row's title; Swap Done overrides it per row
    /// ("swapTXHash" / "approvalTXHash") without duplicating the view.
    let title: String
    let hash: String
    let explorerLink: String
    let showCopy: Bool

    init(title: String = "transactionHash", hash: String, explorerLink: String, showCopy: Bool) {
        self.title = title
        self.hash = hash
        self.explorerLink = explorerLink
        self.showCopy = showCopy
    }

    var hasExplorerLink: Bool {
        explorerLink.isNotEmpty
    }

    var clipboardValue: String {
        hasExplorerLink ? explorerLink : hash
    }

    var body: some View {
        HStack(spacing: 32) {
            Text(title.localized)
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

                if hasExplorerLink {
                    explorerLinkView
                }
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
        ClipboardManager.copyToClipboard(clipboardValue)
    }
}

#Preview {
    TransactionDoneHashRowView(
        hash: "294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        explorerLink: "https://thorchain.net/tx/294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        showCopy: true
    )
}

#Preview("No explorer link") {
    TransactionDoneHashRowView(
        hash: "294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        explorerLink: "",
        showCopy: true
    )
}
