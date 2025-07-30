//
//  Screen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct Screen<Content: View>: View {
    let content: () -> Content
    
    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(Color.backgroundBlue, ignoresSafeAreaEdges: .all)
    }
}

#Preview {
    Screen {
        Text("Hello, world!")
    }
}
