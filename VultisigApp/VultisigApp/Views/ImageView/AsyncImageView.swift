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
    let source: Source
    let size: CGSize
    let ticker: String
    
    enum Source {
        case resource(String)
        case remote(URL?)
    }

    var body: some View {
        ZStack {
            switch source {
            case .resource(let logoName):
                if let image = UIImage(named: logoName) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .cornerRadius(100)
                } else {
                    fallbackText
                }
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
