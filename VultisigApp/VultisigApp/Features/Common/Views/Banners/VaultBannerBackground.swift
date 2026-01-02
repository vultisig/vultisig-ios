//
//  VaultBannerBackground.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/10/2025.
//

import SwiftUI

struct VaultBannerBackground: View {
    let type: VaultBannerType
    
    var body: some View {
        switch type {
        case .upgradeVault:
            upgradeVaultView
        case .backupVault:
            backupVaultView
        case .followVultisig:
            followVultisigView
        }
    }
    
    var upgradeVaultView: some View {
        ZStack(alignment: .trailing) {
            Theme.colors.bgSurface1
            image
        }
    }
    
    var backupVaultView: some View {
        ZStack(alignment: .trailing) {
            Theme.colors.bgSurface1
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.28, green: 0.48, blue: 0.99), location: 0.00),
                    Gradient.Stop(color: Color(red: 0.13, green: 0.33, blue: 0.87).opacity(0.19), location: 1.00),
                ],
                center: UnitPoint(x: 0.5, y: 0.5)
            )
            .frame(width: 228, height: 228)
            .blur(radius: 36.97183)
            .opacity(0.7)
            .offset(x: 60, y: 30)
            Image(type.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 160)
                .offset(x: 25, y: 20)
        }
    }
    
    var followVultisigView: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.02, green: 0.11, blue: 0.23), location: 0.00),
                Gradient.Stop(color: Color(red: 0.13, green: 0.33, blue: 0.87), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.4, y: 0.93),
            endPoint: UnitPoint(x: 0.73, y: -0.35)
        )
        .overlay(image, alignment: .trailing)
    }
    
    var image: some View {
        Image(type.image)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .frame(height: 215)
            .offset(x: 60, y: 30)
    }
}
