//
//  VaultSetupCard.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-30.
//

import SwiftUI

struct VaultSetupCard: View {
    @Environment(\.theme) var theme
    let title: String
    let buttonTitle: String
    let icon: String
    
    var body: some View {
        ZStack {
            content
            button
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue600)
        .cornerRadius(20)
    }
    
    var button: some View {
        VStack {
            Spacer()
            
            PrimaryButton(title: buttonTitle) {}
                .padding(24)
        }
    }
    
    var logo: some View {
        Image(icon)
            .resizable()
            .frame(width: 48, height: 48)
            .padding(.bottom, 18)
    }
    
    var text: some View {
        Text(NSLocalizedString("ThisDeviceIs", comment: ""))
            .font(theme.fonts.caption12)
            .foregroundColor(.neutral0)
    }
    
    var titleContent: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
}

#Preview {
    ZStack {
        Background()
        VaultSetupCard(
            title: "initiatingDevice",
            buttonTitle: "createQR",
            icon: "InitiatingDeviceIcon"
        )
    }
}
