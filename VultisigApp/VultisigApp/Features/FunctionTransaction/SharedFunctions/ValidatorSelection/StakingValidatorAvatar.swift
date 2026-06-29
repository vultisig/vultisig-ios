//
//  StakingValidatorAvatar.swift
//  VultisigApp
//
//  One avatar component for the shared validator picker + selection previews.
//  Renders the deterministic colored-initial monogram, then swaps in the remote
//  image — either a Keybase-resolved URL (Cosmos) via `KeybaseAvatarView`, or a
//  ready logo URL (Solana). Sized by the caller (36 in the card, 20 in the
//  inline selection preview).
//

import SwiftUI

struct StakingValidatorAvatar: View {
    let avatar: StakingValidator.Avatar
    let size: CGFloat

    var body: some View {
        switch avatar {
        case .keybase(let identity, let monogram):
            KeybaseAvatarView(identity: identity, monogram: monogram, size: size)
        case .logo(let url, let monogram):
            ZStack {
                monogramAvatar(monogram)
                if let url {
                    CachedAsyncImage(url: url, urlCache: .imageCache) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } placeholder: {
                        Color.clear
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func monogramAvatar(_ monogram: String) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.colors.primaryAccent3, Theme.colors.primaryAccent4],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(monogram)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }
}
