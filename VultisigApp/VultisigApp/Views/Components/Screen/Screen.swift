//
//  Screen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct Screen<Content: View>: View {
    @Environment(\.screenTitle) private var title
    @Environment(\.screenEdgeInsets) private var edgeInsets
    @Environment(\.screenBackgroundType) private var backgroundType
    @Environment(\.screenNavigationBarHidden) private var navigationBarHidden
    @Environment(\.screenBackButtonHidden) private var backButtonHidden
    @Environment(\.screenIgnoresTopEdge) private var ignoresTopEdge
    @Environment(\.screenToolbarItems) private var toolbarItems

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        container
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundView.ignoresSafeArea())
    }

    @ViewBuilder
    var container: some View {
        if navigationBarHidden {
            contentContainer
        } else {
#if os(macOS)
            VStack {
                contentContainer
                    .crossPlatformToolbar(
                        title,
                        ignoresTopEdge: ignoresTopEdge,
                        showsBackButton: !backButtonHidden,
                        items: toolbarItems
                    )
            }
#else
            contentContainer
                .crossPlatformToolbar(
                    title,
                    ignoresTopEdge: ignoresTopEdge,
                    showsBackButton: !backButtonHidden,
                    items: toolbarItems
                )
#endif
        }
    }

    var contentContainer: some View {
        content()
            .padding(.top, edgeInsets.top ?? verticalPadding)
            .padding(.bottom, edgeInsets.bottom ?? verticalPadding)
            .padding(.leading, edgeInsets.leading ?? horizontalPadding)
            .padding(.trailing, edgeInsets.trailing ?? horizontalPadding)
    }

    var horizontalPadding: CGFloat {
        #if os(iOS)
            return 16
        #else
            return 40
        #endif
    }

    var verticalPadding: CGFloat { 12 }

    @ViewBuilder
    var backgroundView: some View {
        switch backgroundType {
        case .plain:
            Theme.colors.bgPrimary
        case .gradient:
            VaultMainScreenBackground()
        case .clear:
            Color.clear
        }
    }
}

#Preview {
    Screen {
        Text("Hello, world!")
    }
}
