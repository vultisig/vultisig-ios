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
            case .remote(let url):
                if let url = url {
                    CachedAsyncImage(url: url, urlCache: .imageCache) { image in
                        image
                            .resizable()
                            .frame(width: size.width, height: size.height)
                            .cornerRadius(100)
                    } placeholder: {
                        ProgressView()
                            .frame(width: size.width, height: size.height)
                    }
                } else {
                    fallbackText
                }
            }
            
            if let chainIcon = tokenChainLogo, logo != tokenChainLogo {
                Image(chainIcon)
                    .resizable()
                    .frame(width: size.width / 2, height: size.height / 2)
                    .cornerRadius(16)
                    .offset(x: size.width / 2.5, y: size.width / 2.5)
            }
        }
    }

    var fallbackText: some View {
        Text(String(ticker.prefix(1)).uppercased())
            .font(.body16MontserratBold)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .foregroundColor(.blue600)
            .cornerRadius(100)
    }
}
