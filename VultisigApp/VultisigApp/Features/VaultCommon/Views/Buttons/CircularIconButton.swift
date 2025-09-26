//
//  CircularIconButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/09/2025.
//

import SwiftUI

struct CircularIconButton: View {
    @State var isHovered: Bool = false
    let icon: String
    var action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .glassEffect(.regular.tint(isHovered ? .white.opacity(0.1) : .clear).interactive(), in: Circle())
                .buttonStyle(.plain)
        } else {
            button
        }
    }
    
    var button: some View {
        Button(action: action) {
            Icon(named: icon, color: Theme.colors.textPrimary, size: 24)
                .padding(10)
        }
        .onHover { isHovered in
            withAnimation {
                self.isHovered = isHovered
            }
        }
    }
}

#Preview {
    ScrollView {
        CircularIconButton(icon: "settings") {}
        CircularIconButton(icon: "x") {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
