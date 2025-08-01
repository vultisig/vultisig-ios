//
//  InnerHeightPreferenceKey.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct InnerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
