//
//  SetupVaultImageManager.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI

struct SetupVaultImageManager: View {
    @Binding var selectedTab: SetupVaultState
    
    var body: some View {
        VStack(spacing: 12) {
            text
            image
        }
        .padding(24)
        .clipped()
    }
    
    var text: some View {
        Text(selectedTab.getDescription())
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .lineSpacing(8)
            .multilineTextAlignment(.center)
    }
    
    var imageContent: some View {
        Image(selectedTab.getImage())
            .resizable()
            .frame(maxWidth: .infinity)
    }
    
    var image: some View {
        Image(selectedTab.getImage())
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
#if os(macOS)
            .offset(y: 15)
            .scaleEffect(1.1)
#endif
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultImageManager(selectedTab: .constant(.MOfNVaults))
    }
}
