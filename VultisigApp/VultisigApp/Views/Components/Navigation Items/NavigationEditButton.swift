//
//  NavigationEditButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

struct NavigationEditButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Image(systemName: "square.and.pencil")
#if os(iOS)
            .font(.body18MenloBold)
            .foregroundColor(tint)
#elseif os(macOS)
            .font(.body18Menlo)
#endif
    }
}

#Preview {
    ZStack {
        Background()
        NavigationEditButton()
    }
}
