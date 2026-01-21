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
                    CachedAsyncImage(url: url, urlCache: .imageCache) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size.width, height: size.height)
                    } placeholder: {
                        ProgressView()
                            .frame(width: size.width, height: size.height)
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

    var fallbackText: some View {
        Text(String(ticker.prefix(1)).uppercased())
            .font(Theme.fonts.bodyMMedium)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .foregroundColor(Theme.colors.bgSurface1)
            .cornerRadius(100)
    }
}
