//
//  AsyncImageView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.05.2024.
//

import SwiftUI
import Foundation
import VultisigUIResources

extension URLCache {
    static let imageCache = URLCache(memoryCapacity: 100_000_000, diskCapacity: 500_000_000)
}

struct AsyncImageView: View {
    let logo: String
    let size: CGSize
    let ticker: String
    let tokenChainLogo: String?
    let imageData: Data?

    init(
        logo: String,
        size: CGSize,
        ticker: String,
        tokenChainLogo: String?,
        imageData: Data? = nil
    ) {
        self.logo = logo
        self.size = size
        self.ticker = ticker
        self.tokenChainLogo = tokenChainLogo
        self.imageData = imageData
    }

    var source: Source {
        if logo.hasPrefix("https://") {
            return .remote(URL(string: logo))
        } else {
            return .resource(logo)
        }
    }

    enum Source {
        case resource(String)
        case remote(URL?)
    }

    var body: some View {
        ZStack {
            if let image = platformImage(from: imageData) {
                fittedImage(image)
            } else {
                switch source {
                case .resource(let logoName):
                    imageContainer(logoName)
                        .clipShape(Circle())
                case .remote(let url):
                    if let url = url {
                        // Phase-based (not `placeholder:`) so a failed load resolves to
                        // the ticker fallback instead of spinning forever. Long-tail
                        // catalog tokens routinely carry a logo URL that 404s or serves
                        // a non-image body — both surface here as `.failure`.
                        CachedAsyncImage(url: url, urlCache: .imageCache) { phase in
                            switch phase {
                            case .success(let image):
                                fittedImage(image)
                            case .failure:
                                fallbackText
                            case .empty:
                                ProgressView()
                                    .frame(width: size.width, height: size.height)
                            @unknown default:
                                fallbackText
                            }
                        }
                    } else {
                        fallbackText
                    }
                }
            }

            #if !WIDGET_EXTENSION
            if let chainIcon = tokenChainLogo, logo != tokenChainLogo {
                ChainIconView(
                    icon: "chain-" + chainIcon,
                    size: size.width / 4.5
                ).offset(x: size.width / 2.5, y: size.width / 2.5)
            }
            #endif
        }
    }

    private func fittedImage(_ image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .clipShape(Circle())
    }

    private func platformImage(from data: Data?) -> Image? {
        guard let data else { return nil }
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

    func imageContainer(_ logoName: String) -> some View {
        ZStack {
            if let image = VultisigImage(rawValue: logoName) {
                image.image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
            } else {
                #if os(iOS)
                if let image = UIImage(named: logoName) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                } else {
                    fallbackText
                }
                #else
                if let image = NSImage(named: logoName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                } else {
                    fallbackText
                }
                #endif
            }
        }
    }

    var fallbackText: some View {
        #if WIDGET_EXTENSION
        Text(String(ticker.prefix(1)).uppercased())
            .font(WidgetTheme.labelFont(size: size.width * 0.42))
            .frame(width: size.width, height: size.height)
            .background(WidgetTheme.iconFallbackBackground)
            .foregroundStyle(WidgetTheme.background)
            .clipShape(Circle())
        #else
        Text(String(ticker.prefix(1)).uppercased())
            .font(Theme.fonts.bodyMMedium)
            .frame(width: size.width, height: size.height)
            .background(Theme.colors.textPrimary)
            .foregroundStyle(Theme.colors.bgSurface1)
            .cornerRadius(Theme.radius.pill)
        #endif
    }
}
