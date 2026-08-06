//
//  PasscodeFeatureFlag.swift
//  VultisigApp
//

import Foundation

/// Gates the passcode feature while it is built out across several merges.
///
/// Off by default, so the layers below can land without the feature going live:
/// no key material is rewritten and no Settings entry appears. A tester opts in
/// from Settings → Advanced.
///
/// Read straight from `UserDefaults` rather than through `SettingsViewModel`, so
/// that security code reached off the main actor and before any view exists can
/// consult it; reaching for a `@MainActor` view model there would drag the
/// settings layer into the security path for a single boolean.
enum PasscodeFeatureFlag {

    /// Backing key for the `@AppStorage` toggle on `SettingsViewModel`.
    ///
    /// The toggle and every non-view reader resolve the same defaults entry, so
    /// the key lives here instead of as a literal repeated at each site.
    static let defaultsKey = "passcodeFeatureEnabled"

    /// `false` whenever the key is absent, which is what makes "off by default"
    /// hold on a fresh install and on upgrade from a build that predates the
    /// flag.
    static var isEnabled: Bool {
        isEnabled(in: .standard)
    }

    /// Seam for tests — pass an isolated `UserDefaults(suiteName:)` so a test
    /// never mutates the shared store.
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}
