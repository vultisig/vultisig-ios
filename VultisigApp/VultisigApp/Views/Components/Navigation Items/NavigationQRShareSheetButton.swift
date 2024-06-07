//
//  NavigationQRShareSheetButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

struct NavigationQRShareSheetButton: View {
    @Binding var showSheet: Bool
    var tint: Color = Color.neutral0
    
    var body: some View {
        Button(action: {
            showSheet.toggle()
        }) {
            Image(systemName: "arrow.up.doc")
                .font(.body18MenloBold)
                .foregroundColor(tint)
        }
    }
}

#Preview {
    ZStack {
        Background()
        NavigationQRShareSheetButton(showSheet: .constant(true))
    }
}
