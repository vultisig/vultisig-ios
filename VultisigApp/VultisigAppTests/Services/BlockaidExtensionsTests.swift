//
//  BlockaidExtensionsTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Covers the Solana Blockaid scan → `SecurityScannerResult` mapping. The
/// warning sheet only renders when `!isSecure`, so the human-readable risk
/// summary (top-3 `features`) must be attached on the non-secure branch, and
/// an empty `features` array must yield `nil` (not `""`) so the sheet keeps its
/// default copy.
final class BlockaidExtensionsTests: XCTestCase {

    // MARK: - toSolanaSecurityScannerResult

    /// Non-secure scan with features: description is the top-3 features joined
    /// by newline so the warning sheet can surface the actual reasons.
    func test_toSolanaSecurityScannerResult_nonSecureWithFeatures_setsTopThreeDescription() throws {
        let response = try decodeScanResponse(
            resultType: "Malicious",
            features: ["Reason A", "Reason B", "Reason C", "Reason D"]
        )

        let result = try response.toSolanaSecurityScannerResult(provider: "blockaid")

        XCTAssertFalse(result.isSecure)
        XCTAssertEqual(result.description, "Reason A\nReason B\nReason C")
    }

    /// Secure scan with no features: description stays nil (the sheet doesn't
    /// render for secure results anyway).
    func test_toSolanaSecurityScannerResult_secureWithoutFeatures_descriptionNil() throws {
        let response = try decodeScanResponse(resultType: "Benign", features: [])

        let result = try response.toSolanaSecurityScannerResult(provider: "blockaid")

        XCTAssertTrue(result.isSecure)
        XCTAssertNil(result.description)
    }

    /// Empty-guard: a non-secure scan with no features must produce a nil
    /// description, not "", so the sheet falls back to its default copy.
    func test_toSolanaSecurityScannerResult_nonSecureWithoutFeatures_descriptionNil() throws {
        let response = try decodeScanResponse(resultType: "Malicious", features: [])

        let result = try response.toSolanaSecurityScannerResult(provider: "blockaid")

        XCTAssertFalse(result.isSecure)
        XCTAssertNil(result.description)
    }

    // MARK: - BlockaidSolanaValidationJson.toKeysignScannerResult

    func test_solanaKeysignScannerResult_nonSecureWithFeatures_setsTopThreeDescription() throws {
        let validation = try decodeSolanaValidation(
            resultType: "Malicious",
            features: ["Reason A", "Reason B", "Reason C", "Reason D"]
        )

        let result = validation.toKeysignScannerResult(provider: "blockaid")

        XCTAssertFalse(result.isSecure)
        XCTAssertEqual(result.description, "Reason A\nReason B\nReason C")
    }

    func test_solanaKeysignScannerResult_secureWithoutFeatures_descriptionNil() throws {
        let validation = try decodeSolanaValidation(resultType: "Benign", features: [])

        let result = validation.toKeysignScannerResult(provider: "blockaid")

        XCTAssertTrue(result.isSecure)
        XCTAssertNil(result.description)
    }

    func test_solanaKeysignScannerResult_nonSecureWithoutFeatures_descriptionNil() throws {
        let validation = try decodeSolanaValidation(resultType: "Malicious", features: [])

        let result = validation.toKeysignScannerResult(provider: "blockaid")

        XCTAssertFalse(result.isSecure)
        XCTAssertNil(result.description)
    }
}

// MARK: - Fixture helpers

private extension BlockaidExtensionsTests {
    /// Builds a Solana validation JSON body. `features` is the array of
    /// human-readable risk strings Blockaid returns for the Solana shape.
    func validationJSON(resultType: String, features: [String]) -> String {
        let featuresJSON = features
            .map { "\"\($0)\"" }
            .joined(separator: ", ")
        return """
        {
          "result_type": "\(resultType)",
          "reason": "",
          "features": [\(featuresJSON)],
          "extended_features": []
        }
        """
    }

    func decodeScanResponse(
        resultType: String,
        features: [String]
    ) throws -> BlockaidTransactionScanResponseJson {
        let json = """
        {
          "status": "Success",
          "result": {
            "validation": \(validationJSON(resultType: resultType, features: features))
          },
          "error": null,
          "request_id": "r"
        }
        """
        return try JSONDecoder().decode(
            BlockaidTransactionScanResponseJson.self,
            from: Data(json.utf8)
        )
    }

    func decodeSolanaValidation(
        resultType: String,
        features: [String]
    ) throws -> BlockaidTransactionScanResponseJson.BlockaidSolanaResultJson.BlockaidSolanaValidationJson {
        try JSONDecoder().decode(
            BlockaidTransactionScanResponseJson.BlockaidSolanaResultJson.BlockaidSolanaValidationJson.self,
            from: Data(validationJSON(resultType: resultType, features: features).utf8)
        )
    }
}
