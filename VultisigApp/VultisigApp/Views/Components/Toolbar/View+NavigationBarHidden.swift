//
//  View+NavigationBarHidden.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

extension View {
    func customNavigationBarHidden() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarHidden(true)
        #endif
    }
}
