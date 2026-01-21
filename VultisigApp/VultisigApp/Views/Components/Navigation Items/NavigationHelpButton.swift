//
//  NavigationHelpButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct NavigationHelpButton: View {
    var tint: Color = Theme.colors.textPrimary

    var body: some View {
        Link(destination: URL(string: Endpoint.supportDocumentLink)!) {
            image
        }
    }

    var image: some View {
        Image(systemName: "questionmark.circle")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationHelpButton()
    }
}
