//
//  NavigationRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

typealias NavPath = Hashable

final class NavigationRouter: ObservableObject {
    @Published var navPath = NavigationPath() {
        // The stack's own back button, swipe and back menu write the path
        // through its binding and never touch `history`. Every such write is a
        // pop from the tail, so trimming the tail keeps the two aligned; left
        // stale, the predicate pops below count against routes that are no
        // longer on screen.
        didSet {
            let staleCount = history.count - navPath.count
            if staleCount > 0 {
                history.removeLast(staleCount)
            }
        }
    }
    private var history: [any NavPath] = []

    /// The route on top of the stack, or `nil` at the root.
    var topDestination: (any NavPath)? {
        history.last
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

    // The pops below update `history` before `navPath`, so the path's
    // observer finds the two already aligned and trims nothing twice.

    func navigateBack() {
        guard !navPath.isEmpty else { return }
        if !history.isEmpty { history.removeLast() }
        navPath.removeLast()
    }

    func navigateBack(matching predicate: (any NavPath) -> Bool) {
        guard let matchIndex = history.lastIndex(where: predicate) else {
            navigateBack()
            return
        }
        let removeCount = history.count - 1 - matchIndex
        guard removeCount > 0 else { return }
        history.removeLast(removeCount)
        navPath.removeLast(removeCount)
    }

    /// Pops every trailing route that matches `predicate`, and nothing when
    /// the top does not match. Unlike `navigateBack(matching:)` there is no
    /// single-pop fallback.
    func popTrailingRoutes(where predicate: (any NavPath) -> Bool) {
        let removeCount = history.reversed().prefix(while: predicate).count
        guard removeCount > 0 else { return }
        history.removeLast(removeCount)
        navPath.removeLast(removeCount)
    }

    func navigateToRoot() {
        // An empty-path mutation still publishes and invalidates NavigationStack.
        if !navPath.isEmpty {
            navPath.removeLast(navPath.count)
        }
        history.removeAll()
    }
}
