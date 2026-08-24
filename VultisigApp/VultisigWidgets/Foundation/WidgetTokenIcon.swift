//
//  WidgetTokenIcon.swift
//  VultisigWidgets
//

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct WidgetTokenIcon: View {
    let asset: WidgetMarketAsset
    let size: CGFloat

    var body: some View {
        Group {
            if let image = platformImage {
                image
                    .resizable()
                    .scaledToFit()
            } else if asset.id == "bitcoin" {
                Image("BitcoinLogo")
                    .resizable()
                    .scaledToFit()
            } else {
                Circle()
                    .fill(WidgetTheme.separator)
                    .overlay {
                        Text(String(asset.symbol.prefix(1)))
                            .font(WidgetTheme.labelFont(size: size * 0.42))
                            .foregroundStyle(WidgetTheme.primaryText)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var platformImage: Image? {
        guard let data = asset.iconData else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}
