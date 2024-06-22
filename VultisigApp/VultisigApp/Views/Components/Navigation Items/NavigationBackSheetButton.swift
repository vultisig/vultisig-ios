//
//  NavigationBackSheetButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct NavigationBackSheetButton: View {
    @Binding var showSheet: Bool
    var tint: Color = Color.neutral0
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            showSheet.toggle()
        }) {
            Image(systemName: "chevron.backward")
                .font(.body18MenloBold)
#if os(iOS)
                .foregroundColor(tint)
#elseif os(macOS)
                .foregroundColor(colorScheme == .light ? .neutral700 : .neutral0)
#endif
        }
    }
}

#Preview {
    ZStack {
        Background()
        NavigationBackSheetButton(showSheet: .constant(true))
    }
}
