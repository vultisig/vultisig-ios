//
//  NavigationHelpButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct NavigationHelpButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Link(destination: URL(string: Endpoint.supportDocumentLink)!) {
            image
        }
    }
    
    var image: some View {
        Image(systemName: "questionmark.circle")
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
        NavigationHelpButton()
    }
}
