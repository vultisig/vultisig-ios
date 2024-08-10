//
//  NavigationAddButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-10.
//

import SwiftUI

struct NavigationAddButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Image(systemName: "plus")
            .font(.body18MenloBold)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationAddButton()
    }
}
