//
//  ImageView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.05.2024.
//

import SwiftUI

extension URLCache {
    static let imageCache = URLCache(memoryCapacity: 100_000_000, diskCapacity: 500_000_000)
}

struct AsyncImageView: View {
    @State private var uiImage: UIImage? = nil
    @State private var isLoading: Bool = false

    let source: ImageView.Source
    let size: CGSize
    let ticker: String

    var body: some View {
        Group {
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .cornerRadius(100)
            } else if isLoading {
                ProgressView()
                    .frame(width: size.width, height: size.height)
            } else {
                fallbackText
            }
        }
        .onAppear(perform: loadImage)
    }

    var fallbackText: some View {
        Text(String(ticker.prefix(1)).uppercased())
            .font(.body16MontserratBold)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .foregroundColor(.blue600)
            .cornerRadius(100)
    }

    private func loadImage() {
        switch source {
        case .resource(let logoName):
            uiImage = UIImage(named: logoName)
        case .remote(let url):
            guard let url = url else { return }
            isLoading = true
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.uiImage = image
                        self.isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
            }.resume()
        }
    }
}


struct ImageView: View {

    enum Source {
        case resource(String)
        case remote(URL?)
    }

    let source: Source
    let size: CGSize

    init(source: Source, size: CGSize) {
        self.source = source
        self.size = size
    }

    init(_ string: String, size: CGSize) {
        if let url = URL(string: string), url.absoluteString.starts(with: "http") {
            self.init(source: .remote(url), size: size)
        } else {
            self.init(source: .resource(string), size: size)
        }
    }

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
