//
//  ScreenToolbar+EnvironmentKey.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

private struct ScreenToolbarTrailingKey: EnvironmentKey {
    static let defaultValue: AnyView = AnyView(EmptyView())
}

extension EnvironmentValues {
    var screenToolbarTrailing: AnyView {
        get { self[ScreenToolbarTrailingKey.self] }
        set { self[ScreenToolbarTrailingKey.self] = newValue }
    }
}
