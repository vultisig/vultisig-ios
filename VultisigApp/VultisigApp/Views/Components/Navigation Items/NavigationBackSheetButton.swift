//
//  NavigationBackSheetButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct NavigationBackSheetButton: View {
    @Binding var showSheet: Bool
    var tint: Color = Theme.colors.textPrimary
    
    var body: some View {
        Button(action: {
            showSheet.toggle()
        }) {
            Image(systemName: "chevron.backward")
                .font(Theme.fonts.bodyLMedium)
                .foregroundColor(tint)
        }
        .offset(x: -8)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationBackSheetButton(showSheet: .constant(true))
    }
}
