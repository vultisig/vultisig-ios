//
//  Separator.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct Separator: View {
    var color: Color = Theme.colors.textPrimary
    var opacity: CGFloat = 0.2

    var body: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(color)
            .opacity(opacity)
    }
}

#Preview {
    Separator()
}
