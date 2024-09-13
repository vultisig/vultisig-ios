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
            image
            Spacer()
            text
        }
        .padding(24)
        .clipped()
    }
    
    var text: some View {
        Text(selectedTab.label)
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .lineSpacing(8)
            .multilineTextAlignment(.center)
    }
    
    var imageContent: some View {
        Image(selectedTab.image)
            .resizable()
            .frame(maxWidth: .infinity)
            .clipped()
    }
    
    var image: some View {
        Image(selectedTab.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultImageManager(selectedTab: .constant(.secure))
    }
}
