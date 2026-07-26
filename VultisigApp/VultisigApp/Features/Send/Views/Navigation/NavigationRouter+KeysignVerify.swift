//
//  NavigationRouter+KeysignVerify.swift
//  VultisigApp
//
//  Shared retry-pop for the Send-family keysign flow. The unified
//  `SigningKeysignScreen` serves both Send and FunctionCall (whose stack
//  uses `FunctionCallRoute` rather than `SendRoute`), fast + paired. On a
//  broadcast retry the user should land back on their verify screen, so
//  match either flow's `.verify`. Predicate-based (not a hardcoded pop
//  count) so it's correct for both the paired stack (verify -> pairing ->
//  keysign) and the pair-less fast stack (verify -> keysign).
//

import Foundation

extension NavigationRouter {
    func navigateBackToKeysignVerify() {
        navigateBack { destination in
            if let route = destination as? SendRoute, case .verify = route {
                return true
            }
            if let route = destination as? FunctionCallRoute, case .verify = route {
                return true
            }
            return false
        }
    }
}
