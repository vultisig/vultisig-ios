//
//  BlockaidBulkScanTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

final class BlockaidBulkScanTests: XCTestCase {
    private var rpcClient: MockBlockaidRpcClient!
    private var scanner: BlockaidScannerService!

    override func setUp() {
        super.setUp()
        rpcClient = MockBlockaidRpcClient()
        scanner = BlockaidScannerService(blockaidRpcClient: rpcClient)
    }

    override func tearDown() {
        scanner = nil
        rpcClient = nil
        super.tearDown()
    }

    func testSwapWithoutPrecedingTransactionsUsesSingleScan() async throws {
        rpcClient.scanEVMResult = .success(try response(status: "Success", resultType: "Benign"))

        let result = try await scanner.scanTransaction(makeSwap(preceding: []))

        XCTAssertEqual(rpcClient.scanEVMCallCount, 1)
        XCTAssertTrue(rpcClient.scannedEVMBulkTransactions.isEmpty)
        XCTAssertEqual(result.riskLevel, .noRisk)
    }

    func testSwapWithApprovesSendsBulkRequestInSigningOrder() async throws {
        let reset = makeApprove(data: "0xreset")
        let approve = makeApprove(data: "0xapprove")
        let swap = makeSwap(preceding: [reset, approve])
        rpcClient.scanEVMBulkResult = .success(try Array(repeating: response(status: "Success", resultType: "Benign"), count: 3))

        let result = try await scanner.scanTransaction(swap)

        XCTAssertEqual(rpcClient.scanEVMCallCount, 0)
        XCTAssertEqual(rpcClient.scannedEVMBulkTransactions.count, 1)
        let sent = rpcClient.scannedEVMBulkTransactions.first ?? []
        XCTAssertEqual(sent.map(\.data), ["0xreset", "0xapprove", swap.data])
        XCTAssertEqual(sent.map(\.to), [Self.token, Self.token, swap.to])
        XCTAssertEqual(sent.map(\.from), [Self.owner, Self.owner, Self.owner])
        XCTAssertEqual(sent.map(\.value), ["0x0", "0x0", "0x2a"])
        XCTAssertTrue(result.isSecure)
        XCTAssertEqual(result.riskLevel, .noRisk)
    }

    func testBulkVerdictIsTheLeastSecureEntry() async throws {
        rpcClient.scanEVMBulkResult = .success([
            try response(status: "Success", resultType: "Malicious"),
            try response(status: "Success", resultType: "Benign")
        ])

        let result = try await scanner.scanTransaction(makeSwap(preceding: [makeApprove(data: "0xapprove")]))

        XCTAssertFalse(result.isSecure)
        XCTAssertEqual(result.riskLevel, .critical)
    }

    func testBulkEntryErrorFailsTheScan() async throws {
        rpcClient.scanEVMBulkResult = .success([
            try response(status: "Success", resultType: "Benign"),
            try response(status: "Error", resultType: "Error")
        ])

        do {
            _ = try await scanner.scanTransaction(makeSwap(preceding: [makeApprove(data: "0xapprove")]))
            XCTFail("Expected an erroring bulk entry to fail the scan")
        } catch BlockaidScannerError.scannerError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testBulkResultCountMismatchFailsTheScan() async throws {
        rpcClient.scanEVMBulkResult = .success([try response(status: "Success", resultType: "Benign")])

        do {
            _ = try await scanner.scanTransaction(makeSwap(preceding: [makeApprove(data: "0xapprove")]))
            XCTFail("Expected a short bulk response to fail the scan")
        } catch BlockaidScannerError.scannerError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}

private extension BlockaidBulkScanTests {
    static let owner = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    static let token = "0xA0b86991c6218b36c1d19d4a2e9eB0cE3606eB48"
    static let router = "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5"

    func makeApprove(data: String) -> SecurityScannerTransaction {
        SecurityScannerTransaction(
            chain: .ethereum,
            type: .approval,
            from: Self.owner,
            to: Self.token,
            amount: .zero,
            data: data
        )
    }

    func makeSwap(preceding: [SecurityScannerTransaction]) -> SecurityScannerTransaction {
        SecurityScannerTransaction(
            chain: .ethereum,
            type: .swap,
            from: Self.owner,
            to: Self.router,
            amount: BigInt(42),
            data: "0xswap",
            precedingTransactions: preceding
        )
    }

    func response(status: String, resultType: String) throws -> BlockaidTransactionScanResponseJson {
        let json = """
        {"validation":{"status":"\(status)","result_type":"\(resultType)","features":[]},"chain":"ethereum"}
        """
        return try JSONDecoder().decode(BlockaidTransactionScanResponseJson.self, from: Data(json.utf8))
    }
}
