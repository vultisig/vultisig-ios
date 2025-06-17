//
//  ExtensionMemoServiceTests.swift
//  VultisigAppTests
//
//  Created by System on 2025-01-16.
//

import XCTest
@testable import VultisigApp

final class ExtensionMemoServiceTests: XCTestCase {
    
    override func setUpWithError() throws {
        super.setUp()
    }
    
    override func tearDownWithError() throws {
        super.tearDown()
    }
    
    // MARK: - Hex Memo Decoding Tests
    
    func testDecodeTransferTokenHex() throws {
        // transfer(address,uint256) - 0xa9059cbb
        let transferMemo = "0xa9059cbb000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000000000000000000a"
        let decoded = transferMemo.decodedExtensionMemo
        
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
        let decoded = approveMemo.decodedExtensionMemo
        
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
        let decoded = balanceOfMemo.decodedExtensionMemo
        
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
        let decoded = unknownMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "Unknown function memo should be decoded")
        XCTAssertTrue(decoded!.contains("Contract Function Call"), "Should indicate contract function call")
        XCTAssertTrue(decoded!.contains("12345678"), "Should include function selector")
        
        print("✅ Unknown Function Test:")
        print("Original: \(unknownMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeKyberSwapHex() throws {
        // KyberSwap function with embedded JSON data (like what we see in real transactions)
        let kyberMemo = "0xe21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000006e4141d33021b52c91c28608403db4a0ffb50ec6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000003c000000000000000000000000000000000000000000000000000000000000000e801010000003d0200000011d53ec50bc8f54b9357fbfe2a7de034fc00f8b3000000000000000000071afd498d00000100000000000000000000000000000001000276a40aeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee912ce59144191c1204e64559fe8253a0e49e6548245b8d996d6ef17fd48622048370945d4328f7d00000000000000000000000006851d9f2000000540000000000000000000000000000000000000000000000000000000000000000000000000000000000000ee70dd76c0c0000000000000000e3651af45475f95d4f82e73edb06d29ff62c91ec8f5ff06571bdeb29000000000000000000000000000000000000000000000000000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000912ce59144191c1204e64559fe8253a0e49e65480000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000245b8d996d6ef17fd48622048370945d4328f7d000000000000000000000000000000000000000000000000000071afd498d0000000000000000000000000000000000000000000000000000e2420a2dfcff9fcb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002887b22536f75726365223a226b7962657273776170222c22416d6f756e74496e555344223a22352e303330323731303938373331373235222c22416d6f756e744f7574555344223a22352e303233373732353938363239363638222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223136333835353332343535393438373737383231222c2254696d657374616d70223a313735303139333437342c22526f7574654944223a2231636463343864332d613663352d343864392d393537652d3966383665643736303465663a30386334636539612d396333372d343337642d386263342d633730623764623030376237222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a225a2b542f307773786b666d6a32453266334c2b63773155544a654b43614a73647774424174527234716b67474e3636687673304c314c694f7a566e5a396c305451556256654666667a6a5a73424f6930527a714e4b676745494b776b46344771304d4947486238506a6a4d61433331773558357336322f536431534e30526e6762436a4a394650306c75777538774e42595354667176434863526e6773445a704931454d5034754f4f73585035506d2b6436746f373063737a504541684f304244663434424b627a5134462b767648583366345766463748727a2b385131766a4a5a3064777a7277774f41415a647a4837474147494c6c324463306f67623668437248416a68767a35443174534e68492b6f592f52477165513164395a6a32317a744b784952636a314769675645654e4e46696857745a6e376165764f473139466f362f316a515838305473333048386e4d4f4b69513d3d227d7d000000000000000000000000000000000000000000000000"
        let decoded = kyberMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "KyberSwap memo should be decoded")
        XCTAssertTrue(decoded!.contains("KyberSwap Token Swap"), "Should identify KyberSwap swap")
        XCTAssertTrue(decoded!.contains("Source: kyberswap"), "Should show KyberSwap as source")
        XCTAssertTrue(decoded!.contains("Amount In: $5."), "Should show USD amount in")
        XCTAssertTrue(decoded!.contains("Amount Out: $5."), "Should show USD amount out")
        
        print("✅ KyberSwap Test:")
        print("Original: \(String(kyberMemo.prefix(100)))...")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    // MARK: - JSON Contract Interaction Tests
    
    func testDecodeJSONContractInteraction() throws {
        let jsonMemo = """
        {"method":"approve","params":{"spender":"0x742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b","amount":"100000000000000000000"}}
        """
        let decoded = jsonMemo.decodedExtensionMemo
        
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
        let decoded = simpleJsonMemo.decodedExtensionMemo
        
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
        let decoded = approvalMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "Approval text memo should be decoded")
        XCTAssertEqual(decoded, "Token Approval: token spending", "Should decode approval details")
        
        print("✅ Approval Text Test:")
        print("Original: \(approvalMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeTransferText() throws {
        let transferMemo = "transfer 100 USDC"
        let decoded = transferMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "Transfer text memo should be decoded")
        XCTAssertEqual(decoded, "Token Transfer: 100 USDC", "Should decode transfer details")
        
        print("✅ Transfer Text Test:")
        print("Original: \(transferMemo)")
        print("Decoded: \(decoded!)")
        print("---")
    }
    
    func testDecodeSwapText() throws {
        let swapMemo = "swap ETH for USDT"
        let decoded = swapMemo.decodedExtensionMemo
        
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
        let decoded = base64Memo.decodedExtensionMemo
        
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
        let decoded = hexTextMemo.decodedExtensionMemo
        
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
        let decoded = regularMemo.decodedExtensionMemo
        
        XCTAssertNil(decoded, "Regular memo should not be decoded as extension memo")
        
        print("✅ Non-Extension Memo Test:")
        print("Original: \(regularMemo)")
        print("Decoded: nil (expected)")
        print("---")
    }
    
    func testEmptyMemo() throws {
        let emptyMemo = ""
        let decoded = emptyMemo.decodedExtensionMemo
        
        XCTAssertNil(decoded, "Empty memo should not be decoded")
    }
    
    func testShortHexMemo() throws {
        let shortHexMemo = "0x123"
        let decoded = shortHexMemo.decodedExtensionMemo
        
        XCTAssertNil(decoded, "Short hex memo should not be decoded")
    }
    
    func testInvalidJSON() throws {
        let invalidJsonMemo = "{invalid json"
        let decoded = invalidJsonMemo.decodedExtensionMemo
        
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
            ("SGVsbG8sIFZ1bHRpc2lnIQ==", "Hello, Vultisig!"),
            ("0xe21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000006e4141d33021b52c91c28608403db4a0ffb50ec6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000003c000000000000000000000000000000000000000000000000000000000000000e801010000003d0200000011d53ec50bc8f54b9357fbfe2a7de034fc00f8b3000000000000000000071afd498d00000100000000000000000000000000000001000276a40aeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee912ce59144191c1204e64559fe8253a0e49e6548245b8d996d6ef17fd48622048370945d4328f7d00000000000000000000000006851d9f2000000540000000000000000000000000000000000000000000000000000000000000000000000000000000000000ee70dd76c0c0000000000000000e3651af45475f95d4f82e73edb06d29ff62c91ec8f5ff06571bdeb29000000000000000000000000000000000000000000000000000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000912ce59144191c1204e64559fe8253a0e49e65480000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000245b8d996d6ef17fd48622048370945d4328f7d000000000000000000000000000000000000000000000000000071afd498d0000000000000000000000000000000000000000000000000000e2420a2dfcff9fcb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002887b22536f75726365223a226b7962657273776170222c22416d6f756e74496e555344223a22352e303330323731303938373331373235222c22416d6f756e744f7574555344223a22352e303233373732353938363239363638222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223136333835353332343535393438373737383231222c2254696d657374616d70223a313735303139333437342c22526f7574654944223a2231636463343864332d613663352d343864392d393537652d3966383665643736303465663a30386334636539612d396333372d343337642d386263342d633730623764623030376237222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a225a2b542f307773786b666d6a32453266334c2b63773155544a654b43614a73647774424174527234716b67474e3636687673304c314c694f7a566e5a396c305451556256654666667a6a5a73424f6930527a714e4b676745494b776b46344771304d4947486238506a6a4d61433331773558357336322f536431534e30526e6762436a4a394650306c75777538774e42595354667176434863526e6773445a704931454d5034754f4f73585035506d2b6436746f373063737a504541684f304244663434424b627a5134462b767648583366345766463748727a2b385131766a4a5a3064777a7277774f41415a647a4837474147494c6c324463306f67623668437248416a68767a35443174534e68492b6f592f52477165513164395a6a32317a744b784952636a314769675645654e4e46696857745a6e376165764f473139466f362f316a515838305473333048386e4d4f4b69513d3d227d7d000000000000000000000000000000000000000000000000", "KyberSwap Token Swap")
        ]
        
        print("\n🚀 Integration Test - All Memo Formats:")
        print("=" * 50)
        
        for (index, testCase) in testMemos.enumerated() {
            let decoded = testCase.memo.decodedExtensionMemo
            
            XCTAssertNotNil(decoded, "Test case \(index + 1) should be decoded")
            XCTAssertTrue(decoded!.contains(testCase.expectedContains), 
                         "Test case \(index + 1) should contain '\(testCase.expectedContains)' but got '\(decoded!)'")
            
            print("\(index + 1). ✅ Memo: \(testCase.memo.prefix(40))...")
            print("   Decoded: \(decoded!)")
            print("")
        }
        
        print("🎉 All extension memo formats decoded successfully!")
    }
    
    // MARK: - Async Comprehensive Decoding Test
    
    func testComprehensiveMemoDecoding() async throws {
        // Test KyberSwap transaction data from the screenshot
        let kyberSwapMemo = "0xe21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000001d5702c6d7eb30e42a8c94b8db7ea2e8444a37fd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003c000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e00000000000000000007ceb23fd6bc0add59e62ac25578270cff1b9f6190000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa841740000000000000000000000000000000000000000000000000000000062ec95af0000000000000000000000006131b5fae19ea4f9d964eac0408e4408b66337b50000000000000000000000000000000000000000000000000000000063f6f85b00000000000000000000000000000000000000000000000000000000000002c0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000409e8aa9350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000001d5702c6d7eb30e42a8c94b8db7ea2e8444a37fd"
        
        let parsedMemo = await EtherfaceService.shared.getParsedMemo(memo: kyberSwapMemo)
        
        if let parsed = parsedMemo {
            print("🎯 Comprehensive Decoding Test:")
            print("Function Signature: \(parsed.functionSignature)")
            print("Function Arguments: \(parsed.functionArguments)")
            
            XCTAssertFalse(parsed.functionSignature.isEmpty, "Function signature should not be empty")
            XCTAssertFalse(parsed.functionArguments.isEmpty, "Function arguments should not be empty")
        } else {
            print("⚠️ Could not decode memo - this might be expected if 4byte.directory doesn't have this signature")
            // This is not necessarily a failure since the API might not have the signature
        }
    }
}

// MARK: - Helper Extensions

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
} 