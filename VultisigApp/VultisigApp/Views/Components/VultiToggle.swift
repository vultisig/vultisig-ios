//
//  VultiToggle.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/02/2026.
//

import SwiftUI

struct VultiToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { EmptyView() }
            .scaleEffect(0.8)
            .tint(Theme.colors.primaryAccent4)
            .toggleStyle(.switch)
    }
}
