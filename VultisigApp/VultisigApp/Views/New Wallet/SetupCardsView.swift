//
//  SetupCardsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-31.
//

import SwiftUI

struct SetupCardsView: View {
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("setup", comment: "Setup"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
    }
    
    var view: some View {
        VStack(spacing: 12) {
            initiatingDeviceCard
            separator
            pairingDeviceCard
        }
        .padding(16)
    }
    
    var initiatingDeviceCard: some View {
        VaultSetupCard(
            title: "initiatingDevice",
            buttonTitle: "createQR",
            icon: "InitiatingDeviceIcon"
        )
    }
    
    var pairingDeviceCard: some View {
        VaultSetupCard(
            title: "initiatingDevice",
            buttonTitle: "createQR",
            icon: "InitiatingDeviceIcon"
        )
    }
    
    var separator: some View {
        HStack(spacing: 18) {
            GradientSeparator(opacity: 0.1)
            orText
            GradientSeparator(opacity: 0.1)
        }
    }
    
    var orText: some View {
        Text(NSLocalizedString("or", comment: ""))
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
    }
}

#Preview {
    SetupCardsView()
}
