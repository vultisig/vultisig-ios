//
//  BannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/08/2025.
//

import SwiftUI

struct BannerView<Content: View>: View {
    let bgImage: String
    let content: () -> Content

    init(bgImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.bgImage = bgImage
    }

    var body: some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(image)
            .containerStyle()
    }

    var image: some View {
        Image(bgImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}
