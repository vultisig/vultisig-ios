//
//  IsSheetPresentedEnvironmentKey.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/10/2025.
//

import SwiftUI

private struct IsSheetPresentedEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = false
}
extension EnvironmentValues {
    var isSheetPresented: Bool {
        get {
            self[IsSheetPresentedEnvironmentKey.self]
        } set {
            self[IsSheetPresentedEnvironmentKey.self] = newValue
        }
    }
}
