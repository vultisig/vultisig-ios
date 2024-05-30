//
//  ImageView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.05.2024.
//

import SwiftUI

extension URLCache {
    static let imageCache = URLCache(memoryCapacity: 10_000_000, diskCapacity: 100_000_000)
}

struct ImageView: View {

    enum Source {
        case resource(String)
        case remote(URL?)
    }

    let source: Source
    let size: CGSize

    var body: some View {
        ZStack {
            switch source {
            case .resource(let resource):
                Image(resource)
                    .resizable()
                    .frame(width: size.width, height: size.height)
            case .remote(let url):
                CachedAsyncImage(url: url, urlCache: .imageCache) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }
}
