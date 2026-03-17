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

    /// Launch skipping authentication (for tests that don't test auth)
    func launchSkippingAuth() {
        launchArguments += ["-skipAuthentication"]
        launchForTesting()
    }
}
