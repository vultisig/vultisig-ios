//
//  LogGateTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Verifies the A1 resolver's two decisions: the gate (`LogGate.isEnabled`, which
/// selects a live logger vs `Logger(.disabled)`) and the composed OSLog category
/// (`Log.category`). A `Logger`'s enabled state is not portably observable at
/// runtime — `Logger.isEnabled(type:)` is a newer-than-deployment-runtime symbol —
/// so the resolver is verified through these decisions rather than the returned
/// `Logger` object. Runs against the app built in Debug (`LOGGING` present).
final class LogGateTests: XCTestCase {

    private var savedConfig: LogConfig!

    override func setUp() {
        super.setUp()
        savedConfig = LogGate.config
    }

    override func tearDown() {
        LogGate.setConfig(savedConfig)
        super.tearDown()
    }

    func testCategoryComposesFeatureAndLayer() {
        XCTAssertEqual(Log.category(.swap, .service), "swap.service")
        XCTAssertEqual(Log.category(.keysign, .network), "keysign.network")
        XCTAssertEqual(Log.category(.chain, .viewModel), "chain.viewModel")
    }

    func testEnabledCategoryIsGatedOn() {
        LogGate.setConfig(LogConfig(parsing: "*:info"))
        XCTAssertTrue(LogGate.isEnabled(.swap, .service))
        XCTAssertTrue(LogGate.isEnabled(.chain, .network))
    }

    func testDisabledCategoryIsGatedOff() {
        LogGate.setConfig(LogConfig(parsing: "swap:off,*:info"))
        XCTAssertFalse(LogGate.isEnabled(.swap, .service))    // → Logger(.disabled)
        XCTAssertFalse(LogGate.isEnabled(.swap, .network))
        XCTAssertTrue(LogGate.isEnabled(.keygen, .service))   // sibling stays on
    }

    func testRuntimeConfigSwapIsHonored() {
        LogGate.setConfig(LogConfig(parsing: "*:off"))
        XCTAssertFalse(LogGate.isEnabled(.chain, .network))

        LogGate.setConfig(LogConfig(parsing: "*:info"))
        XCTAssertTrue(LogGate.isEnabled(.chain, .network))
    }

    func testFacadeAccessorTargetsExpectedFeature() {
        // The ergonomic accessors resolve to the right feature; layer accessors and
        // the subscript both route through `LogGate.logger` for that feature.
        XCTAssertEqual(Log.swap.feature, .swap)
        XCTAssertEqual(Log.keysign.feature, .keysign)
        XCTAssertEqual(Log.feature(.qbtc).feature, .qbtc)
    }

    func testResolverReturnsALoggerForEveryCategory() {
        // Smoke: resolution never traps for any (feature, layer) pair, enabled or not.
        LogGate.setConfig(LogConfig(parsing: "swap:info,*:off"))
        for feature in LogFeature.allCases {
            for layer in LogLayer.allCases {
                _ = LogGate.logger(feature, layer)
            }
        }
    }
}
