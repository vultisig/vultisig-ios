//
//  GlassEffect.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

private struct GlassEffectModifier<GlassShape: Shape>: ViewModifier {
    let tint: Color?
    let shape: GlassShape

    init(tint: Color? = nil, shape: GlassShape = Circle()) {
        self.tint = tint
        self.shape = shape
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // Only apply glass effect if tint is valid or nil
            if let tint = tint {
                content
                    .glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                content
                    .glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            content
        }
    }
}

public extension View {
    func glassy<GlassShape: Shape>(tint: Color? = nil, shape: GlassShape = Circle()) -> some View {
        modifier(GlassEffectModifier(tint: tint, shape: shape))
    }
}
