//
//  DAppRequestBanner.swift
//  VultisigApp
//

import SwiftUI

/// Informational card showing which dApp produced a keysign request.
///
/// Renders above the transaction hero on Verify and Done screens. Trust
/// decisions stay with Blockaid — the banner only echoes the metadata the
/// dApp self-declared so the signer can sanity-check it.
///
/// Layout mirrors the Windows `DappRequestHeader`: a "Request from" header,
/// then a row with a 32pt circular icon and a name/host stack. Empty proto
/// strings are treated as absent so partially-populated metadata still
/// renders cleanly.
struct DAppRequestBanner: View {
    let metadata: DAppMetadata

    private static let iconSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("dappRequestFrom".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)

            HStack(spacing: 12) {
                icon
                infoStack
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(16)
    }

    @ViewBuilder
    private var icon: some View {
        if let url = remoteIconURL {
            CachedAsyncImage(url: url, urlCache: .imageCache) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .clipShape(Circle())
            } placeholder: {
                placeholderIcon
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            Circle()
                .fill(Theme.colors.bgSurface1)
                .frame(width: Self.iconSize, height: Self.iconSize)
            Image(systemName: "globe")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }

    private var infoStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !metadata.name.isEmpty {
                Text(metadata.name)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            if !metadata.host.isEmpty {
                Text(metadata.host)
                    .font(metadata.name.isEmpty ? Theme.fonts.bodyMMedium : Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var remoteIconURL: URL? {
        guard !metadata.iconURL.isEmpty else { return nil }
        return URL(string: metadata.iconURL)
    }
}

#Preview("Full metadata") {
    DAppRequestBanner(
        metadata: DAppMetadata(
            name: "Cross-chain swaps across 13+ networks | 1inch",
            url: "https://1inch.io/",
            iconURL: "https://1inch.io/favicon.ico"
        )
    )
    .padding()
    .background(Theme.colors.bgPrimary)
}

#Preview("Name only") {
    DAppRequestBanner(
        metadata: DAppMetadata(
            name: "Uniswap",
            url: "",
            iconURL: ""
        )
    )
    .padding()
    .background(Theme.colors.bgPrimary)
}

#Preview("Host fallback") {
    DAppRequestBanner(
        metadata: DAppMetadata(
            name: "",
            url: "https://app.uniswap.org/swap",
            iconURL: ""
        )
    )
    .padding()
    .background(Theme.colors.bgPrimary)
}
