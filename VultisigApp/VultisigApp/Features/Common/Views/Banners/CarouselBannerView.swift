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
            // Reserve room for the close button overlaid at the
            // top-trailing corner so localized copy wraps before it.
            .padding(.trailing, 32)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Decorative layers belong in the proposed card bounds. Keeping the
        // 125pt artwork out of the foreground layout prevents it from changing
        // the geometry of the 81pt carousel card.
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Theme.colors.bgSurface1

                    LinearGradient(
                        stops: [
                            .init(color: Theme.colors.bgSurface1.opacity(0.69), location: 0.5),
                            .init(color: banner.gradientEndColor.opacity(0.69), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    artwork(in: proxy.size.width)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .overlay(
            Theme.radius.xl.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(Theme.radius.xl.shape)
        .contentShape(Theme.radius.xl.shape)
    }

    func artwork(in bannerWidth: CGFloat) -> some View {
        let layout = banner.artworkLayout
        let frameOrigin = layout.frameOrigin(in: bannerWidth)
        let renderedSize = layout.frameSize * layout.scale

        return ZStack {
            artworkCrop(
                layout: layout,
                renderedSize: renderedSize
            )

            // A masked duplicate keeps the upper artwork crisp and blends
            // Figma's 2pt blur into only the bottom of the visible crop.
            artworkCrop(
                layout: layout,
                renderedSize: renderedSize,
                blurRadius: 2
            )
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.48),
                        .init(color: .black, location: 0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: layout.frameSize, height: layout.frameSize)
        .position(
            x: frameOrigin.x + layout.frameSize / 2,
            y: frameOrigin.y + layout.frameSize / 2
        )
    }

    func artworkCrop(
        layout: CarouselBannerArtworkLayout,
        renderedSize: CGFloat,
        blurRadius: CGFloat = 0
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Image(banner.artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: renderedSize, height: renderedSize)
                .offset(layout.offset)
                .blur(radius: blurRadius)
        }
        .frame(width: layout.frameSize, height: layout.frameSize, alignment: .topLeading)
        .clipped()
    }

    var iconTile: some View {
        Image(banner.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: banner.iconSize, height: banner.iconSize)
            .frame(width: 41, height: 41)
            .background(Theme.colors.bgSurface2)
            .clipShape(Theme.radius.lg.shape)
            .overlay(
                Theme.radius.lg.shape
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
            .glassEffect(.regular, in: .circle)
        } else {
            Button(action: action) {
                icon
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .fill(.white.opacity(0.01))
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
                .frame(height: 81)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .background(Theme.colors.bgPrimary)
}
