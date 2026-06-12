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
        // Full-color brand logos carry their own margins, so they sit on a
        // dark disc with a tighter inset than the retired mono glyphs did —
        // mirroring the badge construction on the Windows/extension clients.
        Image(icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size)
            .padding(size / 3)
            .background(Circle().fill(Theme.colors.bgSurface1))
            .overlay(Circle().inset(by: -1).stroke(Theme.colors.bgSurface1, lineWidth: 2))
    }
}
