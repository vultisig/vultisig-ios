//
//  NavigationBlankBackButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-06.
//

import SwiftUI

struct NavigationBlankBackButton: View {
    var tint: Color = Color.neutral0
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Image(systemName: "chevron.backward")
            .font(.body18MenloBold)
#if os(iOS)
                .foregroundColor(tint)
#elseif os(macOS)
                .foregroundColor(colorScheme == .light ? .neutral700 : .neutral0)
#endif
    }
}

#Preview {
    ZStack {
        Background()
        NavigationBlankBackButton()
    }
}
