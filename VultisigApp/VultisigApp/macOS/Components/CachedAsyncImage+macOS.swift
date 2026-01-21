//
//  CachedAsyncImage+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension CachedAsyncImage {
    public init(urlRequest: URLRequest?, urlCache: URLCache = .shared, scale: CGFloat = 1) where Content == Image {
        self.init(urlRequest: urlRequest, urlCache: urlCache, scale: scale) { phase in
            phase.image ?? Image(nsImage: .init())
        }
    }

    func image(from data: Data) throws -> Image {
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        } else {
            throw AsyncImage<Content>.LoadingError()
        }
    }
}
#endif
