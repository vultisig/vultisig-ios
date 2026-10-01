//
//  WalletConnectDesignComponents.swift
//  VultisigApp
//

import SwiftUI

private enum WalletConnectDesignColor {
    static let background = Color(hex: "061B3A")
    static let pageBackground = Color(hex: "02122B")
    static let surface = Color(hex: "11284A")
    static let card = Color(hex: "061B3A")
    static let border = Color(hex: "1B3D66")
    static let divider = Color(hex: "1B3D66")
    static let primary = Color(hex: "0B4EFF")
    static let destructiveSurface = Color(hex: "2A203A")
    static let destructiveBorder = Color(hex: "463149")
    static let destructiveText = Color(hex: "FF827C")
    static let textPrimary = Color(hex: "F0F4FC")
    static let textSecondary = Color(hex: "C9D6E8")
    static let textTertiary = Color(hex: "8295AE")
    static let vaultAccent = Color(hex: "33E6BF")
}

extension Color {
    static var walletConnectBackground: Color { WalletConnectDesignColor.background }
    static var walletConnectPageBackground: Color { WalletConnectDesignColor.pageBackground }
    static var walletConnectSurface: Color { WalletConnectDesignColor.surface }
    static var walletConnectCard: Color { WalletConnectDesignColor.card }
    static var walletConnectBorder: Color { WalletConnectDesignColor.border }
    static var walletConnectDivider: Color { WalletConnectDesignColor.divider }
    static var walletConnectPrimary: Color { WalletConnectDesignColor.primary }
    static var walletConnectDestructiveSurface: Color { WalletConnectDesignColor.destructiveSurface }
    static var walletConnectDestructiveBorder: Color { WalletConnectDesignColor.destructiveBorder }
    static var walletConnectDestructiveText: Color { WalletConnectDesignColor.destructiveText }
    static var walletConnectTextPrimary: Color { WalletConnectDesignColor.textPrimary }
    static var walletConnectTextSecondary: Color { WalletConnectDesignColor.textSecondary }
    static var walletConnectTextTertiary: Color { WalletConnectDesignColor.textTertiary }
    static var walletConnectVaultAccent: Color { WalletConnectDesignColor.vaultAccent }
}

struct WalletConnectSheetHeader: View {
    let title: String
    let onClose: (() -> Void)?

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.walletConnectTextTertiary)
                .frame(width: 54, height: 5)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)

            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Color.walletConnectTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.walletConnectTextPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.walletConnectSurface))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 17)
                .padding(.trailing, 18)
            }
        }
        .frame(height: 64)
    }
}

struct WalletConnectDAppAvatar: View {
    let name: String
    let iconURL: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.walletConnectSurface)

            if let iconURL = iconURL?.nilIfEmpty, let url = URL(string: iconURL) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .empty:
                        ProgressView()
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(Theme.fonts.bodyMMedium)
            .foregroundStyle(Color.walletConnectSurface)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.walletConnectTextPrimary))
    }
}

struct WalletConnectDAppIdentityPanel: View {
    let name: String
    let host: String
    let iconURL: String?
    let verifyContext: WalletConnectVerifyContext?

    var body: some View {
        HStack(spacing: 12) {
            WalletConnectDAppAvatar(name: name, iconURL: iconURL, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Color.walletConnectTextPrimary)
                    .lineLimit(1)
                Text(host)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Color.walletConnectTextTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let verifyContext, !verifyContext.isWarning {
                Label("walletConnectDomainMatches".localized, systemImage: "checkmark.seal")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Color.walletConnectTextTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(Color.walletConnectSurface)
        .overlay(
            Theme.radius.lg.shape
                .stroke(Color.walletConnectBorder, lineWidth: 1)
        )
        .clipShape(Theme.radius.lg.shape)
    }
}

struct WalletConnectCenteredDAppIdentity: View {
    let name: String
    let host: String
    let iconURL: String?
    let verifyContext: WalletConnectVerifyContext?

    var body: some View {
        VStack(spacing: 4) {
            WalletConnectDAppAvatar(name: name, iconURL: iconURL, size: 72)
            Text(name)
                .font(Theme.fonts.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.walletConnectTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(host)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Color.walletConnectTextTertiary)
                .lineLimit(1)
            if let verifyContext, !verifyContext.isWarning {
                Label("walletConnectDomainMatches".localized, systemImage: "checkmark.seal")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Color.walletConnectTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct WalletConnectVaultCard: View {
    let title: String
    let subtitle: String
    var style: WalletConnectVaultStyle = .secure
    var showsChevron = false

    var body: some View {
        HStack(spacing: 14) {
            WalletConnectVaultIcon(style: style)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Color.walletConnectTextPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Color.walletConnectTextTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.walletConnectTextSecondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 76)
        .background(Color.walletConnectSurface)
        .clipShape(Theme.radius.lg.shape)
    }
}

struct WalletConnectMetadataRow: View {
    let label: String
    let value: String
    var iconName: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Color.walletConnectTextTertiary)
            Spacer(minLength: 12)
            if let iconName {
                ChainIconView(icon: "chain-" + iconName, size: 13)
                    .frame(width: 26, height: 26)
            }
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Color.walletConnectTextPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .frame(minHeight: 34)
    }
}

struct WalletConnectDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.walletConnectDivider)
            .frame(height: 1)
    }
}

enum WalletConnectVaultStyle {
    case fast
    case secure

    var iconName: String {
        switch self {
        case .fast: return "bolt.fill"
        case .secure: return "lock.shield.fill"
        }
    }
}

struct WalletConnectVaultIcon: View {
    let style: WalletConnectVaultStyle

    var body: some View {
        Image(systemName: style.iconName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.walletConnectVaultAccent)
    }
}

struct WalletConnectChainDisplay: Hashable {
    let identifier: String
    let name: String
    let chain: Chain?

    var id: String { identifier }

    static func unique(from caip2ChainIds: [String]) -> [WalletConnectChainDisplay] {
        var seen = Set<String>()
        var displays: [WalletConnectChainDisplay] = []
        for caip2ChainId in caip2ChainIds {
            let display = resolve(caip2ChainId)
            guard !seen.contains(display.identifier) else { continue }
            seen.insert(display.identifier)
            displays.append(display)
        }
        return displays
    }

    static func resolve(_ caip2ChainId: String) -> WalletConnectChainDisplay {
        let chain: Chain?
        switch caip2ChainId {
        case "eip155:1": chain = .ethereum
        case "eip155:137": chain = .polygonV2
        case "eip155:42161": chain = .arbitrum
        case "eip155:10": chain = .optimism
        case "eip155:56": chain = .bscChain
        case "eip155:8453": chain = .base
        case "eip155:43114": chain = .avalanche
        default: chain = nil
        }
        return WalletConnectChainDisplay(
            identifier: caip2ChainId,
            name: chain?.name ?? caip2ChainId,
            chain: chain
        )
    }
}

struct WalletConnectNetworkIcon: View {
    let display: WalletConnectChainDisplay
    let size: CGFloat

    var body: some View {
        if let chain = display.chain {
            AsyncImageView(
                logo: chain.logo,
                size: CGSize(width: size, height: size),
                ticker: chain.ticker,
                tokenChainLogo: nil
            )
            .frame(width: size, height: size)
        } else {
            Circle()
                .fill(Color.walletConnectTextPrimary)
                .frame(width: size, height: size)
                .overlay(
                    Text(String(display.name.prefix(1)).uppercased())
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Color.walletConnectSurface)
                )
        }
    }
}

struct WalletConnectDestructiveButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(Color.walletConnectDestructiveText)
                } else {
                    Text(title)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Color.walletConnectDestructiveText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color.walletConnectDestructiveSurface)
            .overlay(
                Capsule().stroke(Color.walletConnectDestructiveBorder, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
