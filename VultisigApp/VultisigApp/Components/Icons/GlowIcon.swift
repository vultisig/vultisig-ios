//
//  GlowIcon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/12/2025.
//

import SwiftUI

struct GlowIcon: View {
    let icon: String

    var body: some View {
        Icon(
            named: icon,
            color: Theme.colors.alertInfo,
            size: 20
        )
        .background(
            Circle()
                .fill(Color(hex: "28BBC1"))
                .blur(radius: 7)
                .opacity(0.5)
        )
        .padding(11)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 2))
    }
}

#Preview {
    GlowIcon(icon: "import-seedphrase")
}
