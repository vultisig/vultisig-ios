//
//  NativeToolbarItem+PreferenceKey.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/10/2025.
//

import SwiftUI

private struct NativeToolbarItemKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isNativeToolbarItem: Bool {
        get { self[NativeToolbarItemKey.self] }
        set { self[NativeToolbarItemKey.self] = newValue }
    }
}
