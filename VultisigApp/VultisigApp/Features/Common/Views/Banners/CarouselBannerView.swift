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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(banner.title)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(banner.subtitle)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                
                PrimaryButton(
                    title: banner.buttonTitle,
                    type: .primarySuccess,
                    size: .mini,
                    action: action
                )
                .frame(maxWidth: 100, alignment: .leading)
                .buttonStyle(.borderless)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            CarouselBannerCloseButton(action: onClose)
        }
        .padding(8)
        .background(backgroundView)
        .containerStyle()
    }

    @ViewBuilder
    var backgroundView: some View {
        switch banner {
        case let type as VaultBannerType:
            VaultBannerBackground(type: type)
        default:
            Theme.colors.bgPrimary
        }
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
            named: "cross-small",
            color: Theme.colors.textPrimary,
            size: 16
        )
    }
}

#Preview {
    VStack {
        CarouselBannerView(banner: VaultBannerType.backupVault) {} onClose: {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .background(Theme.colors.bgPrimary)
    
}
