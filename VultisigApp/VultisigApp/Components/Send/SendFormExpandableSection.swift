//
//  SendFormExpandableSection.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/07/2025.
//

import SwiftUI

struct SendFormExpandableSection<Header: View, Content: View>: View {
    let isExpanded: Bool
    /// Corner radius of the section's bordered container. Defaults to the shared
    /// value used across every Send/Function form; callers that need to match a
    /// different Figma card radius (e.g. the limit-swap accordion) override it.
    let cornerRadius: CGFloat
    let header: () -> Header
    let content: () -> Content

    @State var opacity: CGFloat = 0
    @State var height: CGFloat? = 0

    @State var isExpandedInternal = false

    init(
        isExpanded: Bool,
        cornerRadius: CGFloat = 12,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
        self.cornerRadius = cornerRadius
        self.header = header
        self.content = content
        self._isExpandedInternal = State(initialValue: isExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            header()
            content()
                .padding(.top, 16)
                .transition(.verticalGrowAndFade)
                .showIf(isExpandedInternal)
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .padding(1)
        .onChange(of: isExpanded) { _, _ in
            animate()
        }
        .onLoad {
            animate()
        }
    }

    private func animate() {
        withAnimation(.easeInOut) {
            isExpandedInternal = isExpanded
        }
    }
}
