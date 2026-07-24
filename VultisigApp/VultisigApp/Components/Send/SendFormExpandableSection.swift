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
    /// different Figma card radius (e.g. the limit-swap accordion, or the 2026
    /// Send-details cards) override it.
    let cornerRadius: CGFloat
    /// Inner horizontal padding of the bordered container. Defaults to the shared
    /// value; the 2026 Send-details cards use 16.
    let horizontalPadding: CGFloat
    /// Inner vertical padding of the bordered container. Defaults to the shared
    /// value; the 2026 Send-details cards use 20.
    let verticalPadding: CGFloat
    /// Optional fill behind the bordered container. `nil` keeps the container
    /// transparent (the shared default); the 2026 Send-details cards fill it
    /// with the page background so the card reads as a bordered panel.
    let backgroundColor: Color?
    let header: () -> Header
    let content: () -> Content

    @State var opacity: CGFloat = 0
    @State var height: CGFloat? = 0

    @State var isExpandedInternal = false

    init(
        isExpanded: Bool,
        cornerRadius: CGFloat = 12,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 16,
        backgroundColor: Color? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundColor = backgroundColor
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
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(fill)
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

    @ViewBuilder
    private var fill: some View {
        if let backgroundColor {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
        }
    }

    private func animate() {
        withAnimation(.easeInOut) {
            isExpandedInternal = isExpanded
        }
    }
}
