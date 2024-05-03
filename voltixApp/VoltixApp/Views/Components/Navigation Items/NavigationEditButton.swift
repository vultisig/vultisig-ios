//
//  NavigationEditButton.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

struct NavigationEditButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Image(systemName: "gear")
            .font(.body18MenloBold)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationEditButton()
    }
}
