//
//  LaunchTests.swift
//  VultisigAppUITests
//

import XCTest

final class LaunchTests: VultisigUITestCase {

    func testLaunchScreenshot() throws {
        app.launchForTesting()
        takeScreenshot(name: "Launch Screen")
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
