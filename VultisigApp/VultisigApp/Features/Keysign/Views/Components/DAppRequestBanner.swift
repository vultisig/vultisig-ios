//
//  DAppRequestBanner.swift
//  VultisigApp
//

import SwiftUI

/// Informational banner showing which dApp produced a keysign request.
///
/// Renders above the transaction hero on Verify and Done screens. Trust
/// decisions stay with Blockaid — the banner only echoes the metadata the
/// dApp self-declared so the signer can sanity-check it.
///
/// Layout: 24pt rounded icon + "Request from: <name> (<host>)". Falls back
/// gracefully when individual fields are missing — empty proto strings are
/// treated as absent.
struct DAppRequestBanner: View {
    let metadata: DAppMetadata

    private static let iconSize: CGFloat = 24

    var body: some View {
        HStack(spacing: 8) {
            icon
            label
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var icon: some View {
        if let url = remoteIconURL {
            CachedAsyncImage(url: url, urlCache: .imageCache) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } placeholder: {
                placeholderIcon
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.colors.bgSurface1)
                .frame(width: Self.iconSize, height: Self.iconSize)
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }

    private var label: some View {
        Text(labelString)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// Composed display string. Drops the host parens when the host equals the
    /// name (avoids "Uniswap (uniswap)") or when no host could be parsed, and
    /// substitutes the host for the name when no name was provided.
    private var labelString: String {
        let name = metadata.name
        let host = metadata.host
        let prefix = "dappRequestFrom".localized
        let primary = name.isEmpty ? host : name
        let needsHost = !name.isEmpty && !host.isEmpty && name != host

        if primary.isEmpty {
            return prefix
        }
        return needsHost ? "\(prefix) \(primary) (\(host))" : "\(prefix) \(primary)"
    }

    private var remoteIconURL: URL? {
        guard !metadata.iconURL.isEmpty else { return nil }
        return URL(string: metadata.iconURL)
    }
}

#Preview("Full metadata") {
    DAppRequestBanner(
        metadata: DAppMetadata(
            name: "Uniswap",
            url: "https://app.uniswap.org/swap",
            iconURL: "https://app.uniswap.org/favicon.png"
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
