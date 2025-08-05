//
//  BottomSheetContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct BottomSheetContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.borderBlue)
                .frame(width: 64, height: 4)
                .cornerRadius(99)
            content
        }
        .background(Theme.colors.bgSecondary)
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }
}
