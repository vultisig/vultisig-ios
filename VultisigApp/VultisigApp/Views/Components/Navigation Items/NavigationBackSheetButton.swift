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
    
    var body: some View {
        Button(action: {
            showSheet.toggle()
        }) {
            Image(systemName: "chevron.backward")
#if os(iOS)
                .font(.body18MenloBold)
                .foregroundColor(tint)
#elseif os(macOS)
                .font(.body18Menlo)
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
