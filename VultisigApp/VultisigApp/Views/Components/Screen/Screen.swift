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
    
    let content: () -> Content
    
    init(
        title: String = "",
        showNavigationBar: Bool = true,
        edgeInsets: ScreenEdgeInsets = .noInsets,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showNavigationBar = showNavigationBar
        self.edgeInsets = edgeInsets
        self.content = content
    }
    
    var body: some View {
        container
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.colors.bgPrimary, ignoresSafeAreaEdges: .all)
    }
    
    @ViewBuilder
    var container: some View {
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
}

#Preview {
    Screen {
        Text("Hello, world!")
    }
}
