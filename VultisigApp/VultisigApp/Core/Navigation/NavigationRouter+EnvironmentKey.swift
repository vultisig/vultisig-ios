//
//  NavigationRouter+EnvironmentKey.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct NavigationRouterKey: EnvironmentKey {
    static let defaultValue: NavigationRouter = NavigationRouter()
}

extension EnvironmentValues {
    var router: NavigationRouter {
        get { self[NavigationRouterKey.self] }
        set { self[NavigationRouterKey.self] = newValue }
    }
}
