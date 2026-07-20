//
//  NavigationEditButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

struct NavigationEditButton: View {
    var body: some View {
        Icon(.penWritingFilled, color: Theme.colors.textPrimary, size: 16)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationEditButton()
    }
}
