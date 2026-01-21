//
//  CircleIcon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/12/2025.
//

import SwiftUI

struct CircleIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        Icon(
            named: icon,
            color: color,
            size: 27
        )
        .padding(10)
        .background(
            Circle()
                .inset(by: 1)
                .fill(color.opacity(0.2))
                .strokeBorder(color, lineWidth: 1.5)
        )
    }
}

#Preview {
    CircleIcon(
        icon: "active-chain",
        color: Theme.colors.alertError
    )
}
