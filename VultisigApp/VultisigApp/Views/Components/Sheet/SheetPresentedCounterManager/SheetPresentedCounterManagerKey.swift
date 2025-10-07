//
//  SheetPresentedCounterManagerKey.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/10/2025.
//

import SwiftUI

// Environment key for the manager
struct SheetPresentedCounterManagerKey: EnvironmentKey {
    static let defaultValue: SheetPresentedCounterManager = SheetPresentedCounterManager()
}

extension EnvironmentValues {
    var sheetPresentedCounterManager: SheetPresentedCounterManager {
        get { self[SheetPresentedCounterManagerKey.self] }
        set { self[SheetPresentedCounterManagerKey.self] = newValue }
    }
}
