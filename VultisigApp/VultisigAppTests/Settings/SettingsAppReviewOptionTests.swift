//
//  SettingsAppReviewOptionTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class SettingsAppReviewOptionTests: XCTestCase {
    func testRateAppOpensAppStoreWriteReviewAction() throws {
        guard case .link(let url) = SettingsOption.rateApp.type else {
            return XCTFail("Rate the App must open a direct link")
        }

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "apps.apple.com")
        XCTAssertEqual(components.path, "/app/vultisig/id6503023896")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "action", value: "write-review")])
    }

    func testRateAppUsesLocalizedTitleAndSparkleIcon() {
        XCTAssertEqual(SettingsOption.rateApp.title, "rateTheApp")
        XCTAssertNotEqual(SettingsOption.rateApp.title.localized, SettingsOption.rateApp.title)
        XCTAssertEqual(SettingsOption.rateApp.icon, .stars)
    }
}
