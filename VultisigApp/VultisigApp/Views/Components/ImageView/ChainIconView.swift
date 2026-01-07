//
//  ChainIconView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/10/2025.
//

import SwiftUI

struct ChainIconView: View {
    let icon: String
    let size: CGFloat
    
    var body: some View {
        Image(icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size)
            .padding(size / 2)
            .background(Circle().fill(Theme.colors.textPrimary))
            .overlay(Circle().inset(by: -1).stroke(Theme.colors.bgSurface1, lineWidth: 2))
    }
}
