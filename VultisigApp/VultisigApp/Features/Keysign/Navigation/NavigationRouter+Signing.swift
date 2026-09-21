//
//  NavigationRouter+Signing.swift
//  VultisigApp
//

import Foundation

extension NavigationRouter {
    /// Whether the top of the stack is a pairing or keysign screen.
    var isShowingSigningRoute: Bool {
        topDestination is SigningRoute
    }

    /// Pops the pairing and keysign screens and lands on whatever screen
    /// started the signing flow. Pops nothing when the top is not a
    /// `SigningRoute`.
    func navigateBackOutOfSigning() {
        popTrailingRoutes { $0 is SigningRoute }
    }
}
