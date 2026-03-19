//
//  Screen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct Screen<Content: View>: View {
    @Environment(\.screenTitle) private var envTitle
    @Environment(\.screenEdgeInsets) private var envEdgeInsets
    @Environment(\.screenBackgroundType) private var envBackgroundType
    @Environment(\.screenNavigationBarHidden) private var envNavigationBarHidden
    @Environment(\.screenBackButtonHidden) private var backButtonHidden
    @Environment(\.screenIgnoresTopEdge) private var ignoresTopEdge
    @Environment(\.screenToolbarItems) private var toolbarItems

    // Legacy overrides from deprecated init
    private var legacyTitle: String?
    private var legacyNavigationBarHidden: Bool?
    private var legacyEdgeInsets: ScreenEdgeInsets?
    private var legacyBackgroundType: ScreenBackgroundType?

    private var title: String { legacyTitle ?? envTitle }
    private var edgeInsets: ScreenEdgeInsets { legacyEdgeInsets ?? envEdgeInsets }
    private var backgroundType: ScreenBackgroundType { legacyBackgroundType ?? envBackgroundType }
    private var navigationBarHidden: Bool { legacyNavigationBarHidden ?? envNavigationBarHidden }

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    /// Deprecated initializer — use environment modifiers instead:
    /// `.screenTitle()`, `.screenNavigationBarHidden()`, `.screenEdgeInsets()`, `.screenBackground()`
    @available(*, deprecated, message: "Use Screen {} with .screenTitle(), .screenNavigationBarHidden(), .screenEdgeInsets(), .screenBackground() modifiers")
    init(
        title: String = "",
        showNavigationBar: Bool = true,
        edgeInsets: ScreenEdgeInsets = .noInsets,
        backgroundType: ScreenBackgroundType = .plain,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content
        self.legacyTitle = title
        self.legacyNavigationBarHidden = !showNavigationBar
        self.legacyEdgeInsets = edgeInsets
        self.legacyBackgroundType = backgroundType
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
