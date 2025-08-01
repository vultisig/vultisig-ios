//
//  Screen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct Screen<Content: View>: View {
    let title: String
    let content: () -> Content
    
    init(title: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        container
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.backgroundBlue, ignoresSafeAreaEdges: .all)
    }
    
    @ViewBuilder
    var container: some View {
#if os(macOS)
        VStack {
            GeneralMacHeader(title: title)
            contentContainer
        }
#else
        contentContainer
            .navigationTitle(title)
#endif
    }
    
    var contentContainer: some View {
        content()
            .padding(.vertical, 24)
            .padding(.horizontal, horizontalPadding)
    }
    
    var horizontalPadding: CGFloat {
        #if os(iOS)
            return 16
        #else
            return 40
        #endif
    }
}

#Preview {
    Screen {
        Text("Hello, world!")
    }
}
