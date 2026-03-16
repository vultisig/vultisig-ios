//
//  XCUIApplication+Launch.swift
//  VultisigAppUITests
//

import XCTest

extension XCUIApplication {

    /// Launch with standard test configuration
    func launchForTesting() {
        launchArguments += ["-UITesting"]
        launchArguments += ["-disableAnimations"]
        launchEnvironment["UI_TESTING"] = "1"
        launch()
    }

    /// Launch with a specific vault pre-selected (via launch environment)
    func launchWithVault(named name: String) {
        launchEnvironment["TEST_VAULT_NAME"] = name
        launchForTesting()
    }

    /// Launch skipping authentication (for tests that don't test auth)
    func launchSkippingAuth() {
        launchArguments += ["-skipAuthentication"]
        launchForTesting()
    }
}
