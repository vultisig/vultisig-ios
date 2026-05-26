//
//  FunctionCallAddressValidationTests.swift
//  VultisigAppTests
//
//  Regression coverage for the THOR/MAYA/TON/Cosmos multi-chain
//  address validation that previously lived inside the legacy
//  `FunctionCallAddressTextField.validateAddress(_:)`. After the
//  AddressTextField migration, this validation lives in
//  `FunctionCallAddressValidation` and is referenced by the
//  per-sub-model `addressError` computed properties.
//

import XCTest
@testable import VultisigApp

final class FunctionCallAddressValidationTests: XCTestCase {

    /// Pin: legacy `validateAddress(_:)` returned `false` for empty +
    /// random strings. We surface the error only when the user has
    /// typed something — empty input is treated as "no error yet" so
    /// the field doesn't show red on first render.
    func testErrorForThorMayaTONIsNilForEmpty() {
        XCTAssertNil(FunctionCallAddressValidation.errorForThorMayaTON(""))
        XCTAssertNil(FunctionCallAddressValidation.errorForThorMayaTON("   "))
    }

    func testErrorForThorMayaTONSurfacesForGarbageInput() {
        XCTAssertNotNil(FunctionCallAddressValidation.errorForThorMayaTON("not-a-valid-address"))
        XCTAssertNotNil(FunctionCallAddressValidation.errorForThorMayaTON("0x1234"))
    }

    func testIsValidThorMayaTONRejectsGarbage() {
        XCTAssertFalse(FunctionCallAddressValidation.isValidThorMayaTON("garbage"))
    }

    func testCosmosFallbackUsesThorMayaTONWhenChainNil() {
        // Without a chain context the helper falls back to the
        // THOR/Maya/TON multi-chain validity check — matches the legacy
        // behaviour for sub-models that didn't pass `chain:`.
        XCTAssertFalse(FunctionCallAddressValidation.isValidCosmos("garbage", chain: nil))
    }
}
