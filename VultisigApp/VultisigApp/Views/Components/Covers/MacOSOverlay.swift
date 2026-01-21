//
//  MacOSOverlay.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct MacOSOverlay: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .frame(height: 200)
                .offset(y: -200)

            Color.black
        }
        .opacity(0.8)
    }
}
