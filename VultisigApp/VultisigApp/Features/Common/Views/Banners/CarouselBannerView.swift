//
//  CarouselBannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct CarouselBannerView<Banner: CarouselBannerType>: View {
    let banner: Banner
    let action: () -> Void
    let onClose: () -> Void

    init(
        banner: Banner,
        action: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.banner = banner
        self.action = action
        self.onClose = onClose
    }

    var body: some View {
        // The whole card is the primary action. It's a `Button` (not a bare
        // `onTapGesture`) so the close button — layered on top as a sibling
        // overlay — reliably wins its own hit region: two buttons hit-test to
        // the frontmost, whereas `onTapGesture` + `Button` can both fire.
        Button(action: action) {
            card
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // Figma places the 40pt glass close button 10pt from the banner's
            // top-right edge (its content offsets past the 20pt padding).
            CarouselBannerCloseButton(action: onClose)
                .padding(10)
        }
    }

    var card: some View {
        HStack(spacing: 12) {
            iconTile

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.leading)
                Text(banner.subtitle)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Reserve room for the close button overlaid at the top-trailing
            // corner (40pt control, 10pt inset → ~50pt from the edge) so long
            // localized copy wraps before it instead of running underneath.
            .padding(.trailing, 32)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.colors.bgSurface1)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    var iconTile: some View {
        Icon(banner.icon, color: banner.iconColor, size: 20)
            .frame(width: 41, height: 41)
            .background(Theme.colors.bgSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.colors.borderExtraLight, lineWidth: 1)
            )
    }
}

private struct CarouselBannerCloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button(action: action) {
                icon
                    .padding(12)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        } else {
            Button(action: action) {
                icon
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    var icon: some View {
        Icon(
            .crossSmall,
            color: Theme.colors.textPrimary,
            size: 16
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach(VaultBannerType.allCases) { banner in
            CarouselBannerView(banner: banner) {} onClose: {}
                .frame(height: 128)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .background(Theme.colors.bgPrimary)
}
