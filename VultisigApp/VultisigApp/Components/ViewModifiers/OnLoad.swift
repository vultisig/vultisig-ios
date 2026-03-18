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

private struct OnLoadAsyncModifier: ViewModifier {
    @State var didLoad = false
    let action: () async -> Void

    init(perform action: @escaping (() async -> Void)) {
        self.action = action
    }

    func body(content: Content) -> some View {
        content.task {
            if didLoad == false {
                didLoad = true
                await action()
            }
        }
    }
}

public extension View {
    func onLoad(perform action: @escaping () -> Void) -> some View {
        modifier(OnLoadModifier(perform: action))
    }

    func onLoad(perform action: @escaping () async -> Void) -> some View {
        modifier(OnLoadAsyncModifier(perform: action))
    }
}
