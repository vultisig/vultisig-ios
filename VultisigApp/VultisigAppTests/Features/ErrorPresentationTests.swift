//
//  ErrorPresentationTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class ErrorPresentationTests: XCTestCase {

    // MARK: - Catalogued kinds

    func testTransactionFailedIsCritical() {
        let presentation = ErrorPresentation(.transactionFailed)
        XCTAssertEqual(presentation.title, "transactionFailed".localized)
        XCTAssertEqual(presentation.description, "transactionFailedDescription".localized)
        XCTAssertEqual(presentation.type, .alert)
        XCTAssertNil(presentation.rawError)
    }

    func testNetworkUnstableIsWarning() {
        let presentation = ErrorPresentation(.networkUnstable)
        XCTAssertEqual(presentation.title, "errorNetworkUnstableTitle".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testInsufficientFundsIsWarning() {
        let presentation = ErrorPresentation(.insufficientFunds)
        XCTAssertEqual(presentation.title, "swapErrorInsufficientFundsTitle".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testCameraPermissionIsWarning() {
        let presentation = ErrorPresentation(.cameraPermission)
        XCTAssertEqual(presentation.title, "errorCameraPermissionTitle".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testSameVaultShareIsWarning() {
        let presentation = ErrorPresentation(.sameVaultShare)
        XCTAssertEqual(presentation.title, "sameDeviceShareError".localized)
        XCTAssertEqual(presentation.description, "sameDeviceShareErrorDescription".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testVaultNotLoadedIsWarning() {
        let presentation = ErrorPresentation(.vaultNotLoaded)
        XCTAssertEqual(presentation.title, "errorVaultNotLoadedTitle".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testVaultNameInUseIsWarning() {
        let presentation = ErrorPresentation(.vaultNameInUse)
        XCTAssertEqual(presentation.title, "vaultNameAlreadyInUse".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testSeedPhraseAlreadyImportedIsWarning() {
        let presentation = ErrorPresentation(.seedPhraseAlreadyImported)
        XCTAssertEqual(presentation.title, "seedPhraseAlreadyImported".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testRawErrorIsThreadedThrough() {
        let presentation = ErrorPresentation(.vaultNameInUse, rawError: "trace")
        XCTAssertEqual(presentation.rawError, "trace")
    }

    // MARK: - Signing classifier

    func testSigningInsufficientFundsMapsToWarning() {
        let presentation = ErrorPresentation.signing(rawError: "broadcast failed: insufficient funds for gas")
        XCTAssertEqual(presentation.title, "swapErrorInsufficientFundsTitle".localized)
        XCTAssertEqual(presentation.type, .warning)
        XCTAssertEqual(presentation.rawError, "broadcast failed: insufficient funds for gas")
    }

    func testSigningNetworkErrorMapsToWarning() {
        let presentation = ErrorPresentation.signing(rawError: "The network connection was lost.")
        XCTAssertEqual(presentation.title, "errorNetworkUnstableTitle".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testSigningTimeoutMapsToNetwork() {
        let presentation = ErrorPresentation.signing(rawError: "Request timed out")
        XCTAssertEqual(presentation.type, .warning)
        XCTAssertEqual(presentation.title, "errorNetworkUnstableTitle".localized)
    }

    func testSigningUnknownMapsToTransactionFailedCritical() {
        let raw = "javax.crypto.AEADBadTagException: BAD_DECRYPT"
        let presentation = ErrorPresentation.signing(rawError: raw)
        XCTAssertEqual(presentation.title, "transactionFailed".localized)
        XCTAssertEqual(presentation.type, .alert)
        XCTAssertEqual(presentation.rawError, raw)
    }

    func testSigningEmptyRawErrorHasNilDisclosure() {
        let presentation = ErrorPresentation.signing(rawError: "")
        XCTAssertEqual(presentation.type, .alert)
        XCTAssertNil(presentation.rawError)
    }

    // MARK: - Unknown fallback

    func testUnknownMapsToTransactionFailedWithRaw() {
        let presentation = ErrorPresentation.unknown(rawError: "some opaque failure")
        XCTAssertEqual(presentation.title, "transactionFailed".localized)
        XCTAssertEqual(presentation.type, .alert)
        XCTAssertEqual(presentation.rawError, "some opaque failure")
    }

    func testUnknownEmptyRawErrorHasNilDisclosure() {
        let presentation = ErrorPresentation.unknown(rawError: "")
        XCTAssertNil(presentation.rawError)
    }

    // MARK: - Keygen factory

    func testKeygenNetworkErrorBecomesNetworkUnstable() {
        let presentation = ErrorPresentation.keygen(title: "keygenFailed".localized, rawError: "could not connect to host")
        XCTAssertEqual(presentation.title, "errorNetworkUnstableTitle".localized)
        XCTAssertEqual(presentation.type, .warning)
    }

    func testKeygenGenericKeepsTitleAsCritical() {
        let title = "keygenFailed".localized
        let presentation = ErrorPresentation.keygen(title: title, rawError: "tss internal failure")
        XCTAssertEqual(presentation.title, title)
        XCTAssertEqual(presentation.type, .alert)
        XCTAssertEqual(presentation.rawError, "tss internal failure")
    }

    func testKeygenEmptyRawErrorHasNilDisclosure() {
        let presentation = ErrorPresentation.keygen(title: "keygenFailed".localized, rawError: "")
        XCTAssertNil(presentation.rawError)
    }
}
