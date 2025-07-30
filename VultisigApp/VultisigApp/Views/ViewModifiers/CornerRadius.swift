//
//  CornerRadius.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct CornerRadiusModifier: ViewModifier {
    let radius: CGFloat
    let corners: UIRectCorner

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

public extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        modifier(CornerRadiusModifier(radius: radius, corners: corners))
    }
}
