//
//  NavigationBlankBackButton+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-16.
//

#if os(iOS)
import SwiftUI

extension NavigationBlankBackButton {
    var body: some View {
        image
            .offset(x: -8)
    }
}
#endif
