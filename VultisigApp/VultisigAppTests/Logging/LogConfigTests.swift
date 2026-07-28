//
//  LogConfigTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Locks the `VULTI_LOG` grammar and the most-specific-wins precedence of the
/// logging gate (`* | feature | .layer | feature.layer`, exact > feature > layer
/// > wildcard, ties broken by last-declared). Pure — no OSLog backend involved.
final class LogConfigTests: XCTestCase {

    func testWildcardAppliesToEveryCategory() {
        let config = LogConfig(parsing: "*:info")
        XCTAssertEqual(config.minLevel(.swap, .service), .info)
        XCTAssertEqual(config.minLevel(.keygen, .network), .info)
        XCTAssertTrue(config.isEnabled(.chain, .other))
    }

    func testFeatureSelectorBeatsWildcard() {
        let config = LogConfig(parsing: "swap:debug,*:info")
        XCTAssertEqual(config.minLevel(.swap, .service), .debug)
        XCTAssertEqual(config.minLevel(.swap, .view), .debug)   // whole feature
        XCTAssertEqual(config.minLevel(.keygen, .service), .info)
    }

    func testLayerSelectorBeatsWildcard() {
        let config = LogConfig(parsing: ".network:off,*:info")
        XCTAssertFalse(config.isEnabled(.keygen, .network))     // layer disabled
        XCTAssertFalse(config.isEnabled(.tss, .network))
        XCTAssertEqual(config.minLevel(.keygen, .service), .info)
    }

    func testExactSelectorBeatsFeatureAndLayer() {
        let config = LogConfig(parsing: "swap:info,.service:warning,swap.service:debug,*:off")
        XCTAssertEqual(config.minLevel(.swap, .service), .debug)    // exact
        XCTAssertEqual(config.minLevel(.swap, .view), .info)        // feature
        XCTAssertEqual(config.minLevel(.keygen, .service), .warning) // layer
        XCTAssertEqual(config.minLevel(.keygen, .view), .off)       // wildcard
    }

    func testFeatureBeatsLayerWhenBothMatch() {
        // feature (specificity 2) outranks layer (specificity 1).
        let config = LogConfig(parsing: "swap:off,.network:debug")
        XCTAssertFalse(config.isEnabled(.swap, .network))          // feature wins → off
        XCTAssertEqual(config.minLevel(.keygen, .network), .debug) // only layer matches
    }

    func testLastDeclaredWinsOnSpecificityTie() {
        XCTAssertEqual(LogConfig(parsing: "*:info,*:debug").minLevel(.swap, .service), .debug)
        XCTAssertEqual(LogConfig(parsing: "swap:error,swap:debug").minLevel(.swap, .service), .debug)
    }

    func testOffDisablesOnlyTheMatchedCategory() {
        let config = LogConfig(parsing: "swap:off,*:info")
        XCTAssertFalse(config.isEnabled(.swap, .service))
        XCTAssertFalse(config.isEnabled(.swap, .network))
        XCTAssertTrue(config.isEnabled(.keygen, .service))
    }

    func testLevelThresholdGatesLowerLevels() {
        let config = LogConfig(parsing: "swap:warning")
        XCTAssertTrue(config.isEnabled(.swap, .service, .error))
        XCTAssertTrue(config.isEnabled(.swap, .service, .warning))
        XCTAssertFalse(config.isEnabled(.swap, .service, .info))
        XCTAssertFalse(config.isEnabled(.swap, .service, .debug))
    }

    func testMalformedSelectorsAreIgnored() {
        // `feature.` (trailing empty), bare `.`, bare layer names, and unknown
        // tokens are all rejected → no rules → the fallback applies.
        let config = LogConfig(parsing: "swap.:debug,.:info,network:warning,bogus:info,swap.bogus:debug",
                               fallback: .off)
        XCTAssertFalse(config.isEnabled(.swap, .service))
        XCTAssertFalse(config.isEnabled(.keygen, .network))
    }

    func testValidLayerFormIsAccepted() {
        let config = LogConfig(parsing: ".network:warning", fallback: .off)
        XCTAssertEqual(config.minLevel(.swap, .network), .warning)
        XCTAssertEqual(config.minLevel(.keygen, .network), .warning)
        XCTAssertEqual(config.minLevel(.swap, .service), .off)   // no matching rule → fallback
    }

    func testEmptyStringFallsBackToFallback() {
        XCTAssertEqual(LogConfig(parsing: "", fallback: .info).minLevel(.swap, .service), .info)
        XCTAssertEqual(LogConfig(parsing: "   ", fallback: .off).minLevel(.swap, .service), .off)
    }

    func testWhitespaceAndLevelCaseAreTolerated() {
        let config = LogConfig(parsing: " swap : DEBUG , * : Off ")
        XCTAssertEqual(config.minLevel(.swap, .service), .debug)
        XCTAssertFalse(config.isEnabled(.keygen, .service))
    }
}
