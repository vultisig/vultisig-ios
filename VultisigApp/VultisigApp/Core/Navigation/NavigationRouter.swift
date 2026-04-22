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
    private var history: [any NavPath] = []

    init(navPath: NavigationPath = NavigationPath()) {
        self.navPath = navPath
    }

    func replace(to destination: any NavPath) {
        navPath = NavigationPath()
        history.removeAll()
        navPath.append(destination)
        history.append(destination)
    }

    func navigate(to destination: any NavPath) {
        navPath.append(destination)
        history.append(destination)
    }

    func navigateBack() {
        guard !navPath.isEmpty else { return }
        navPath.removeLast()
        if !history.isEmpty { history.removeLast() }
    }

    func navigateBack(matching predicate: (any NavPath) -> Bool) {
        guard let matchIndex = history.lastIndex(where: predicate) else {
            navigateBack()
            return
        }
        let removeCount = history.count - 1 - matchIndex
        guard removeCount > 0 else { return }
        navPath.removeLast(removeCount)
        history.removeLast(removeCount)
    }

    func navigateToRoot() {
        navPath.removeLast(navPath.count)
        history.removeAll()
    }
}
