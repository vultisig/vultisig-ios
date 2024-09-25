//
//  NavigationButton+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//
#if os(iOS)
import SwiftUI

extension NavigationButton {
    var container: some View {
        content
            .foregroundColor(tint)
    }
}
#endif
