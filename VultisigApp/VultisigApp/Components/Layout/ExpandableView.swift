//
//  ExpandableView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct ExpandableView<Header: View, Content: View>: View {
    @Binding var isExpanded: Bool
    let header: () -> Header
    let content: () -> Content

    @State var isExpandedInternal = false

    init(
        isExpanded: Binding<Bool>,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isExpanded = isExpanded
        self.header = header
        self.content = content
        self._isExpandedInternal = State(initialValue: isExpanded.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            header()
                .contentShape(Rectangle())
                .onTapGesture {
                    isExpanded.toggle()
                }
            content()
                .transition(.verticalGrowAndFade)
                .showIf(isExpandedInternal)
        }
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
