//
//  IconButtonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct IconButtonView: View {
    let icon: ImageResource
    let isLoading: Bool

    init(
        icon: ImageResource,
        isLoading: Bool = false
    ) {
        self.icon = icon
        self.isLoading = isLoading
    }

    var body: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(0.7)
        } else {
            Icon(icon)
        }
    }
}

#Preview {
    IconButtonView(icon: .chevronRight)
}
