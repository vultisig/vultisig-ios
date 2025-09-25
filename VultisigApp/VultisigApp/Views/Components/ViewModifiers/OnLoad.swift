//
//  OnLoad.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import SwiftUI

private struct OnLoadModifier: ViewModifier {
    @State var didLoad = false
    let action: () -> Void

    init(perform action: @escaping (() -> Void)) {
        self.action = action
    }

    func body(content: Content) -> some View {
        content.onAppear {
            if didLoad == false {
                didLoad = true
                action()
            }
        }
    }
}

public extension View {
    func onLoad(perform action: @escaping () -> Void) -> some View {
        modifier(OnLoadModifier(perform: action))
    }
}
