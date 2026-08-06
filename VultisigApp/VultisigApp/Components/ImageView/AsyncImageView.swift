//
//  AsyncImageView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.05.2024.
//

import SwiftUI
import Foundation

extension URLCache {
    static let imageCache = URLCache(memoryCapacity: 100_000_000, diskCapacity: 500_000_000)
}

struct AsyncImageView: View {
    let logo: String
    let size: CGSize
    let ticker: String
    let tokenChainLogo: String?

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
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: size.width, height: size.height)
                                // Matched to the `.resource` branch above. Bundled coin
                                // art is drawn circular, but remote art is whatever the
                                // source published — square logos (SOLO, EQ) rendered as
                                // squares in a list of circles until this clip existed.
                                .clipShape(Circle())
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

            if let chainIcon = tokenChainLogo, logo != tokenChainLogo {
                ChainIconView(
                    icon: "chain-" + chainIcon,
                    size: size.width / 4.5
                ).offset(x: size.width / 2.5, y: size.width / 2.5)
            }
        }
    }

    func imageContainer(_ logoName: String) -> some View {
        ZStack {
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

    var fallbackText: some View {
        Text(String(ticker.prefix(1)).uppercased())
            .font(Theme.fonts.bodyMMedium)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .foregroundStyle(Theme.colors.bgSurface1)
            .cornerRadius(Theme.radius.pill)
    }
}
