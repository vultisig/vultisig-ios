//
//  SendFormExpandableSection.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/07/2025.
//

import SwiftUI

struct SendFormExpandableSection<Header: View, Content: View>: View {
    let isExpanded: Bool
    /// Corner radius of the section's bordered container. Defaults to the
    /// container step: a form section is the outer surface on its screen, and
    /// the fields inside it keep the smaller step so the nesting still reads.
    let cornerRadius: CornerRadius
    /// Inner horizontal padding of the bordered container.
    let horizontalPadding: CGFloat
    /// Inner vertical padding of the bordered container.
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

    /// The defaults are the 2026 Send-details card: `xl` / 16 / 20. Those cards
    /// are this same view with the new design already applied, so making them
    /// the default is what "like send" means rather than a number picked off a
    /// different screen.
    init(
        isExpanded: Bool,
        cornerRadius: CornerRadius = Theme.radius.xl,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 20,
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
            cornerRadius.shape
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
            cornerRadius.shape
                .fill(backgroundColor)
        }
    }

    private func animate() {
        withAnimation(.easeInOut) {
            isExpandedInternal = isExpanded
        }
    }
}
