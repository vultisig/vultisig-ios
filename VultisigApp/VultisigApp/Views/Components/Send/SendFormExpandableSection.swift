//
//  SendFormExpandableSection.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/07/2025.
//

import SwiftUI

struct SendFormExpandableSection<Header: View, Content: View>: View {
    let isExpanded: Bool
    let header: () -> Header
    let content: () -> Content

    @State var opacity: CGFloat = 0
    @State var height: CGFloat? = 0

    @State var isExpandedInternal = false

    init(
        isExpanded: Bool,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
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
            RoundedRectangle(cornerRadius: 12)
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
