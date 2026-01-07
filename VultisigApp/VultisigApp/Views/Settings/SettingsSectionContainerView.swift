//
//  SettingsSectionContainerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 19/08/2025.
//

import SwiftUI

struct SettingsSectionContainerView<Content: View>: View {
    var content: () -> Content
    
    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.colors.bgSurface1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
