//
//  NavigationBlankBackButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-06.
//

import SwiftUI

struct NavigationBlankBackButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Image(systemName: "chevron.backward")
            .font(.body16MenloMedium)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationBlankBackButton()
    }
}
