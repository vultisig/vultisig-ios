//
//  NavigationBackButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct NavigationBackButton: View {
    var tint: Color = Color.neutral0
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Button(action: {
            dismiss()
        }) {
            Image(systemName: "chevron.backward")
                .font(.body18MenloBold)
                .foregroundColor(tint)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationBackButton()
    }
}
