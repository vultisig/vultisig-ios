//
//  Icon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct Icon: View {
    let resource: ImageResource
    let color: Color?
    let size: CGFloat

    init(_ resource: ImageResource, color: Color? = Theme.colors.primaryAccent4, size: CGFloat = 20) {
        self.resource = resource
        self.color = color
        self.size = size
    }

    var body: some View {
        Image(resource)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(color) // foregroundColor (deprecated) accepts an optional Color; foregroundStyle requires non-optional
    }
}
