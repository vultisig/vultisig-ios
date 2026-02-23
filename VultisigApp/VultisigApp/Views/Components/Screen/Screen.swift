//
//  Screen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct Screen<Content: View>: View {
    let title: String
    let edgeInsets: ScreenEdgeInsets
    let showNavigationBar: Bool
    let showsBackButton: Bool
    let ignoresTopEdge: Bool
    let toolbarItems: [CustomToolbarItem]
    let backgroundType: BackgroundType

    private let usesCustomToolbar: Bool

    let content: () -> Content

    init(
        title: String = "",
        showNavigationBar: Bool = true,
        edgeInsets: ScreenEdgeInsets = .noInsets,
        backgroundType: BackgroundType = .plain,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showNavigationBar = showNavigationBar
        self.showsBackButton = true
        self.ignoresTopEdge = false
        self.toolbarItems = []
        self.usesCustomToolbar = false
        self.edgeInsets = edgeInsets
        self.backgroundType = backgroundType
        self.content = content
    }

    init(
        title: String = "",
        showsBackButton: Bool = true,
        ignoresTopEdge: Bool = false,
        edgeInsets: ScreenEdgeInsets = .noInsets,
        backgroundType: BackgroundType = .plain,
        @ViewBuilder content: @escaping () -> Content,
        @CustomToolbarItemsBuilder toolbarItems: () -> [CustomToolbarItem]
    ) {
        self.title = title
        self.showNavigationBar = true
        self.showsBackButton = showsBackButton
        self.ignoresTopEdge = ignoresTopEdge
        self.toolbarItems = toolbarItems()
        self.usesCustomToolbar = true
        self.edgeInsets = edgeInsets
        self.backgroundType = backgroundType
        self.content = content
    }

    var body: some View {
        container
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundView.ignoresSafeArea())
    }

    @ViewBuilder
    var container: some View {
        if usesCustomToolbar {
#if os(macOS)
            VStack {
                contentContainer
                    .crossPlatformToolbar(
                        title,
                        ignoresTopEdge: ignoresTopEdge,
                        showsBackButton: showsBackButton,
                        items: toolbarItems
                    )
            }
#else
            contentContainer
                .crossPlatformToolbar(
                    title,
                    ignoresTopEdge: ignoresTopEdge,
                    showsBackButton: showsBackButton,
                    items: toolbarItems
                )
#endif
        } else {
#if os(macOS)
            VStack {
                contentContainer
                    .if(showNavigationBar) {
                        $0.crossPlatformToolbar(title)
                    }
            }
#else
            contentContainer
                .if(showNavigationBar) {
                    $0.crossPlatformToolbar(title)
                }
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

    enum BackgroundType {
        case plain
        case gradient
        case clear
    }
}

#Preview {
    Screen {
        Text("Hello, world!")
    }
}
