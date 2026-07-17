//
//  Icon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

/// Renders an icon from the asset catalog.
///
/// Takes an `ImageResource` rather than a `String` so a missing or misspelled icon is a
/// compile error instead of a blank space at runtime. There is deliberately no SF Symbol
/// path: everything `Icon` draws comes from the Icons V3 set in `Assets.xcassets/Icons`.
struct Icon: View {
    let image: ImageResource
    let color: Color?
    let size: CGFloat

    init(_ image: ImageResource, color: Color? = Theme.colors.primaryAccent4, size: CGFloat = 20) {
        self.image = image
        self.color = color
        self.size = size
    }

    var body: some View {
        Image(image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(color) // foregroundColor (deprecated) accepts an optional Color; foregroundStyle requires non-optional
    }
}
