//
//  NavigationRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

typealias NavPath = Hashable

final class NavigationRouter: ObservableObject {
    @Published var navPath: NavigationPath

    init(navPath: NavigationPath = NavigationPath()) {
        self.navPath = navPath
    }

    func replace(to destination: any NavPath) {
        navPath = NavigationPath()
        navPath.append(destination)
    }

    func navigate(to destination: any NavPath) {
        navPath.append(destination)
    }

    func navigateBack() {
        guard !navPath.isEmpty else { return }
        navPath.removeLast()
    }

    func navigateToRoot() {
        navPath.removeLast(navPath.count)
    }
}
