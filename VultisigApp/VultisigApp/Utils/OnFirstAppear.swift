//
//  OnFirstAppear.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-31.
//

import SwiftUI

struct OnFirstAppear: ViewModifier {
    let perform: () -> Void

    @State private var firstTime = true

    func body(content: Content) -> some View {
        content.onAppear {
            if firstTime {
                firstTime = false
                perform()
            }
        }
    }
}
