//
//  ExtensionMemoServiceTests.swift
//  VultisigAppTests
//
//  Created by System on 2025-01-16.
//

import XCTest
@testable import VultisigApp

final class ExtensionMemoServiceTests: XCTestCase {
    
    var extensionMemoService: ExtensionMemoService!
    
    override func setUpWithError() throws {
        super.setUp()
        extensionMemoService = ExtensionMemoService.shared
    }
    
    override func tearDownWithError() throws {
        extensionMemoService = nil
        super.tearDown()
    }
    
    // MARK: - Hex Memo Decoding Tests
    
    func testDecodeTransferTokenHex() throws {
        // transfer(address,uint256) - 0xa9059cbb
        let transferMemo = "0xa9059cbb000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000000000000000000a"
        let decoded = extensionMemoService.decodeExtensionMemo(transferMemo)
        
        XCTAssertNotNil(decoded, "Transfer memo should be decoded")
        XCTAssertEqual(decoded, "Transfer Token", "Should decode to 'Transfer Token'")
        
        print("✅ Transfer Token Test:")
        print("Original: \(transferMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeApproveTokenHex() throws {
        // approve(address,uint256) - 0x095ea7b3
        let approveMemo = "0x095ea7b3000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000016345785d8a0000"
        let decoded = extensionMemoService.decodeExtensionMemo(approveMemo)
        
        XCTAssertNotNil(decoded, "Approve memo should be decoded")
        XCTAssertEqual(decoded, "Approve Token Spending", "Should decode to 'Approve Token Spending'")
        
        print("✅ Approve Token Test:")
        print("Original: \(approveMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeBalanceOfHex() throws {
        // balanceOf(address) - 0x70a08231
        let balanceOfMemo = "0x70a08231000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b"
        let decoded = extensionMemoService.decodeExtensionMemo(balanceOfMemo)
        
        XCTAssertNotNil(decoded, "BalanceOf memo should be decoded")
        XCTAssertEqual(decoded, "Get Balance", "Should decode to 'Get Balance'")
        
        print("✅ Get Balance Test:")
        print("Original: \(balanceOfMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeUnknownFunctionSelector() throws {
        // Unknown function selector
        let unknownMemo = "0x12345678000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b"
        let decoded = extensionMemoService.decodeExtensionMemo(unknownMemo)
        
        XCTAssertNotNil(decoded, "Unknown function memo should be decoded")
        XCTAssertTrue(decoded!.contains("Contract Function Call"), "Should indicate contract function call")
        XCTAssertTrue(decoded!.contains("12345678"), "Should include function selector")
        
        print("✅ Unknown Function Test:")
        print("Original: \(unknownMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    // MARK: - JSON Contract Interaction Tests
    
    func testDecodeJSONContractInteraction() throws {
        let jsonMemo = """
        {"method":"approve","params":{"spender":"0x742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b","amount":"100000000000000000000"}}
        """
        let decoded = extensionMemoService.decodeExtensionMemo(jsonMemo)
        
        XCTAssertNotNil(decoded, "JSON memo should be decoded")
        XCTAssertTrue(decoded!.contains("Contract: approve"), "Should indicate contract method")
        XCTAssertTrue(decoded!.contains("Parameters:"), "Should include parameters")
        
        print("✅ JSON Contract Test:")
        print("Original: \(jsonMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeSimpleJSONMethod() throws {
        let simpleJsonMemo = """
        {"method":"transfer"}
        """
        let decoded = extensionMemoService.decodeExtensionMemo(simpleJsonMemo)
        
        XCTAssertNotNil(decoded, "Simple JSON memo should be decoded")
        XCTAssertEqual(decoded, "Contract: transfer", "Should decode to contract method")
        
        print("✅ Simple JSON Test:")
        print("Original: \(simpleJsonMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    // MARK: - Action-Based Memo Tests
    
    func testDecodeApprovalText() throws {
        let approvalMemo = "approve token spending"
        let decoded = extensionMemoService.decodeExtensionMemo(approvalMemo)
        
        XCTAssertNotNil(decoded, "Approval text memo should be decoded")
        XCTAssertEqual(decoded, "Token Approval: token spending", "Should decode approval details")
        
        print("✅ Approval Text Test:")
        print("Original: \(approvalMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeTransferText() throws {
        let transferMemo = "transfer 100 USDC"
        let decoded = extensionMemoService.decodeExtensionMemo(transferMemo)
        
        XCTAssertNotNil(decoded, "Transfer text memo should be decoded")
        XCTAssertEqual(decoded, "Token Transfer: 100 USDC", "Should decode transfer details")
        
        print("✅ Transfer Text Test:")
        print("Original: \(transferMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeSwapText() throws {
        let swapMemo = "swap ETH for USDT"
        let decoded = extensionMemoService.decodeExtensionMemo(swapMemo)
        
        XCTAssertNotNil(decoded, "Swap text memo should be decoded")
        XCTAssertEqual(decoded, "Token Swap: ETH for USDT", "Should decode swap details")
        
        print("✅ Swap Text Test:")
        print("Original: \(swapMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    // MARK: - Base64 Decoding Tests
    
    func testDecodeBase64Memo() throws {
        // "Hello, Vultisig!" encoded in base64
        let base64Memo = "SGVsbG8sIFZ1bHRpc2lnIQ=="
        let decoded = extensionMemoService.decodeExtensionMemo(base64Memo)
        
        XCTAssertNotNil(decoded, "Base64 memo should be decoded")
        XCTAssertEqual(decoded, "Hello, Vultisig!", "Should decode base64 content")
        
        print("✅ Base64 Test:")
        print("Original: \(base64Memo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    // MARK: - Hex Text Decoding Tests
    
    func testDecodeHexText() throws {
        // "VultisigExtension" in hex
        let hexTextMemo = "0x56756c74697369674578746656756c74697369674578746656756c74697369674578746573696f6e"
        let decoded = extensionMemoService.decodeExtensionMemo(hexTextMemo)
        
        XCTAssertNotNil(decoded, "Hex text memo should be decoded")
        // Should decode the readable portion or show truncated hex
        XCTAssertTrue(decoded!.count > 0, "Should produce some decoded output")
        
        print("✅ Hex Text Test:")
        print("Original: \(hexTextMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    // MARK: - Edge Cases and Negative Tests
    
    func testNonExtensionMemo() throws {
        let regularMemo = "regular memo text"
        let decoded = extensionMemoService.decodeExtensionMemo(regularMemo)
        
        XCTAssertNil(decoded, "Regular memo should not be decoded as extension memo")
        
        print("✅ Non-Extension Memo Test:")
        print("Original: \(regularMemo)")
        print("Decoded: nil (expected)")
        print("---")
    }
    
    func testEmptyMemo() throws {
        let emptyMemo = ""
        let decoded = extensionMemoService.decodeExtensionMemo(emptyMemo)
        
        XCTAssertNil(decoded, "Empty memo should not be decoded")
    }
    
    func testShortHexMemo() throws {
        let shortHexMemo = "0x123"
        let decoded = extensionMemoService.decodeExtensionMemo(shortHexMemo)
        
        XCTAssertNil(decoded, "Short hex memo should not be decoded")
    }
    
    func testInvalidJSON() throws {
        let invalidJsonMemo = "{invalid json"
        let decoded = extensionMemoService.decodeExtensionMemo(invalidJsonMemo)
        
        XCTAssertNil(decoded, "Invalid JSON should not be decoded")
    }
    
    // MARK: - Integration Test
    
    func testAllMemoFormats() throws {
        let testMemos: [(memo: String, expectedContains: String)] = [
            ("0xa9059cbb000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000000000000000000a", "Transfer Token"),
            ("0x095ea7b3000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000016345785d8a0000", "Approve Token Spending"),
            ("{\"method\":\"approve\",\"params\":{\"spender\":\"0x742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b\",\"amount\":\"100000000000000000000\"}}", "Contract: approve"),
            ("approve token spending", "Token Approval"),
            ("transfer 100 USDC", "Token Transfer"),
            ("swap ETH for USDT", "Token Swap"),
            ("SGVsbG8sIFZ1bHRpc2lnIQ==", "Hello, Vultisig!")
        ]
        
        print("\n🚀 Integration Test - All Memo Formats:")
        print("=" * 50)
        
        for (index, testCase) in testMemos.enumerated() {
            let decoded = extensionMemoService.decodeExtensionMemo(testCase.memo)
            
            XCTAssertNotNil(decoded, "Test case \(index + 1) should be decoded")
            XCTAssertTrue(decoded!.contains(testCase.expectedContains), 
                         "Test case \(index + 1) should contain '\(testCase.expectedContains)' but got '\(decoded!)'")
            
            print("\(index + 1). ✅ Memo: \(testCase.memo.prefix(40))...")
            print("   Decoded: \(decoded!)")
            print("")
        }
        
        print("🎉 All extension memo formats decoded successfully!")
    }
}

// MARK: - Helper Extensions

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
} 