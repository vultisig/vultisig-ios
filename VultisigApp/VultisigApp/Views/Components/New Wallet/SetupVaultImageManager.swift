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
            Spacer()
            imageContent
            Spacer()
            text
        }
        .clipped()
        .padding(.vertical, 16)
    }
    
    var text: some View {
        Text(selectedTab.label)
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .lineSpacing(8)
            .multilineTextAlignment(.center)
            .font(.body12MontserratSemiBold)
    }
    
    var imageContent: some View {
        Image(selectedTab.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 500)
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultImageManager(selectedTab: .constant(.secure))
    }
}
