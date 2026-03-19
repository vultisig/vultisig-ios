//
//  XCUIElement+Helpers.swift
//  VultisigAppUITests
//

import XCTest

extension XCUIElement {

    /// Wait for element to exist, then tap
    @discardableResult
    func waitAndTap(timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) -> Self {
        let exists = waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Element '\(identifier)' not found after \(timeout)s", file: file, line: line)
        tap()
        return self
    }

    /// Tap only if the element exists (no assertion failure)
    @discardableResult
    func tapIfExists(timeout: TimeInterval = 2) -> Self {
        if waitForExistence(timeout: timeout) {
            tap()
        }
        return self
    }

    /// Clear text field and type new text
    @discardableResult
    func clearAndType(_ text: String) -> Self {
        guard exists else { return self }
        tap()

        // Triple-tap to select all, then type over it
        tap(withNumberOfTaps: 3, numberOfTouches: 1)
        typeText(text)
        return self
    }

    /// Assert element label contains expected text
    func assertLabelContains(
        _ text: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let labelValue = label
        XCTAssertTrue(
            labelValue.contains(text),
            "Expected label to contain '\(text)', got '\(labelValue)'",
            file: file,
            line: line
        )
    }

    /// Wait until element is no longer visible
    func waitForDisappearance(timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Element '\(identifier)' still exists after \(timeout)s", file: file, line: line)
    }
}
