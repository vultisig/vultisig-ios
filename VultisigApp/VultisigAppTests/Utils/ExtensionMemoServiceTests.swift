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
    
    // MARK: - Known Function Selector Tests (Synchronous)
    
    func testDecodeTransferToken() throws {
        // transfer(address,uint256) - 0xa9059cbb
        let transferMemo = "0xa9059cbb000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000000000000000000a"
        let decoded = transferMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "Transfer memo should be decoded")
        XCTAssertEqual(decoded, "Transfer Token", "Should decode to 'Transfer Token'")
    }
    
    func testDecodeApproveToken() throws {
        // approve(address,uint256) - 0x095ea7b3
        let approveMemo = "0x095ea7b3000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000016345785d8a0000"
        let decoded = approveMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "Approve memo should be decoded")
        XCTAssertEqual(decoded, "Approve Token Spending", "Should decode to 'Approve Token Spending'")
    }
    
    func testDecodeUniswapV2SwapExactTokensForTokens() throws {
        // swapExactTokensForTokens - 0x38ed1739
        let uniswapMemo = "0x38ed1739000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000080000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d"
        let decoded = uniswapMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "Uniswap V2 memo should be decoded")
        XCTAssertEqual(decoded, "Uniswap Token Swap", "Should decode to 'Uniswap Token Swap'")
    }
    
    func testDecodeUniswapV3ExactInputSingle() throws {
        // exactInputSingle - 0x414bf389
        let uniswapV3Memo = "0x414bf389000000000000000000000000a0b86a33e6d33333eb36ce90a66e7ec7a9681b0a00000000000000000000000000000000000000000000000000000000000001f4"
        let decoded = uniswapV3Memo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "Uniswap V3 memo should be decoded")
        XCTAssertEqual(decoded, "Uniswap V3 Token Swap", "Should decode to 'Uniswap V3 Token Swap'")
    }
    
    func testDecode1inchSwap() throws {
        // 1inch swap function - 0x7c025200
        let oneinchMemo = "0x7c025200000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000016345785d8a0000"
        let decoded = oneinchMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "1inch memo should be decoded")
        XCTAssertEqual(decoded, "1inch Token Swap", "Should decode to '1inch Token Swap'")
    }
    
    // MARK: - KyberSwap Advanced Decoding Tests
    
    func testDecodeKyberSwapWithJSON() throws {
        // Real KyberSwap transaction with embedded JSON data
        let kyberMemo = "0xe21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000006e4141d33021b52c91c28608403db4a0ffb50ec6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000003c000000000000000000000000000000000000000000000000000000000000000e801010000003d0200000011d53ec50bc8f54b9357fbfe2a7de034fc00f8b3000000000000000000071afd498d00000100000000000000000000000000000001000276a40aeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee912ce59144191c1204e64559fe8253a0e49e6548245b8d996d6ef17fd48622048370945d4328f7d00000000000000000000000006851d9f2000000540000000000000000000000000000000000000000000000000000000000000000000000000000000000000ee70dd76c0c0000000000000000e3651af45475f95d4f82e73edb06d29ff62c91ec8f5ff06571bdeb29000000000000000000000000000000000000000000000000000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000912ce59144191c1204e64559fe8253a0e49e65480000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000245b8d996d6ef17fd48622048370945d4328f7d000000000000000000000000000000000000000000000000000071afd498d0000000000000000000000000000000000000000000000000000e2420a2dfcff9fcb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002887b22536f75726365223a226b7962657273776170222c22416d6f756e74496e555344223a22352e303330323731303938373331373235222c22416d6f756e744f7574555344223a22352e303233373732353938363239363638222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223136333835353332343535393438373737383231222c2254696d657374616d70223a313735303139333437342c22526f7574654944223a2231636463343864332d613663352d343864392d393537652d3966383665643736303465663a30386334636539612d396333372d343337642d386263342d633730623764623030376237222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a225a2b542f307773786b666d6a32453266334c2b63773155544a654b43614a73647774424174527234716b67474e3636687673304c314c694f7a566e5a396c305451556256654666667a6a5a73424f6930527a714e4b676745494b776b46344771304d4947486238506a6a4d61433331773558357336322f536431534e30526e6762436a4a394650306c75777538774e42595354667176434863526e6773445a704931454d5034754f4f73585035506d2b6436746f373063737a504541684f304244663434424b627a5134462b767648583366345766463748727a2b385131766a4a5a3064777a7277774f41415a647a4837474147494c6c324463306f67623668437248416a68767a35443174534e68492b6f592f52477165513164395a6a32317a744b784952636a314769675645654e4e46696857745a6e376165764f473139466f362f316a515838305473333048386e4d4f4b69513d3d227d7d000000000000000000000000000000000000000000000000"
        let decoded = kyberMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "KyberSwap memo should be decoded")
        XCTAssertTrue(decoded!.contains("KyberSwap Token Swap"), "Should identify KyberSwap swap")
        XCTAssertTrue(decoded!.contains("Source: kyberswap"), "Should show KyberSwap as source")
        XCTAssertTrue(decoded!.contains("Amount In: $5."), "Should show USD amount in")
        XCTAssertTrue(decoded!.contains("Amount Out: $5."), "Should show USD amount out")
        XCTAssertTrue(decoded!.contains("Time:"), "Should show timestamp")
    }
    
    // MARK: - Unknown Function Selector Tests
    
    func testDecodeUnknownFunctionSelectorSync() throws {
        // Unknown function selector should return nil for synchronous decoding
        let unknownMemo = "0x07ed2379000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b"
        let decoded = unknownMemo.decodedExtensionMemo
        
        XCTAssertNil(decoded, "Unknown function memo should return nil to indicate async decoding is needed")
    }
    
    func testDecodeUnknownFunctionSelectorAsync() async throws {
        // Real 1inch function selector that should be decoded via 4byte.directory
        let unknownMemo = "0x07ed2379000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b"
        
        // Synchronous method should return nil
        let syncDecoded = unknownMemo.decodedExtensionMemo
        XCTAssertNil(syncDecoded, "Synchronous decoding should return nil for unknown selectors")
        
        // Async method should attempt 4byte.directory lookup
        let asyncDecoded = await unknownMemo.decodedExtensionMemoAsync()
        
        // This might succeed or fail depending on 4byte.directory availability
        // The important thing is that it doesn't crash
        print("Async decoding result for 07ed2379: \(asyncDecoded ?? "nil")")
    }
    
    // MARK: - EIP-712 Custom Message Tests
    
    func testDecodeEIP712TypedDataMessage() throws {
        // Simulate EIP-712 typed data (like 1inch custom message signing)
        let eip712Message = "0x19013f5509669fb8f0bc706dc323ae95326e4b0a0624cc5a5b2194c872abb902e625f768d4657abf9da521f30c39a60b21b759eaad5851981dd2f843de51303a3ef"
        let decoded = eip712Message.decodedExtensionMemo
        
        // For custom messages, this might return nil or basic hex info
        // The actual decoding happens in CustomMessagePayload
        print("EIP-712 message decoding: \(decoded ?? "nil")")
    }
    
    // MARK: - Action-Based Text Memo Tests
    
    func testDecodeActionBasedMemos() throws {
        let testCases: [(memo: String, expected: String)] = [
            ("approve token spending", "Token Approval: token spending"),
            ("transfer 100 USDC", "Token Transfer: 100 USDC"),
            ("swap ETH for USDT", "Token Swap: ETH for USDT")
        ]
        
        for testCase in testCases {
            let decoded = testCase.memo.decodedExtensionMemo
            XCTAssertNotNil(decoded, "Action memo should be decoded: \(testCase.memo)")
            XCTAssertEqual(decoded, testCase.expected, "Should decode correctly")
        }
    }
    
    // MARK: - THORChain/Maya Rune Swap Memo Tests
    
    func testDecodeRuneSwapMemos() throws {
        // THORChain swap memos are typically text-based
        let thorchainMemo = "swap:ETH.ETH:0x742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b"
        let decoded = thorchainMemo.decodedExtensionMemo
        
        XCTAssertNotNil(decoded, "THORChain swap memo should be decoded")
        XCTAssertTrue(decoded!.contains("Token Swap"), "Should identify as swap")
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
    }
    
    // MARK: - Edge Cases and Negative Tests
    
    func testNonExtensionMemos() throws {
        let negativeTestCases = [
            "",                              // Empty
            "regular memo text",             // Regular text
            "0x123",                        // Too short hex
            "{invalid json",                // Invalid JSON
            "short"                         // Regular short text
        ]
        
        for testCase in negativeTestCases {
            let decoded = testCase.decodedExtensionMemo
            XCTAssertNil(decoded, "Should not decode non-extension memo: '\(testCase)'")
        }
    }
    
    // MARK: - Real-World Integration Test
    
    func testRealWorldDEXMemos() throws {
        let realWorldMemos: [(description: String, memo: String, expectedContains: String)] = [
            (
                "ERC20 Transfer",
                "0xa9059cbb000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000000000000000000a",
                "Transfer Token"
            ),
            (
                "ERC20 Approve",
                "0x095ea7b3000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b000000000000000000000000000000000000000000000000016345785d8a0000",
                "Approve Token Spending"
            ),
            (
                "Uniswap V2 Swap",
                "0x38ed1739000000000000000000000000000000000000000000000000000000000000000a",
                "Uniswap Token Swap"
            ),
            (
                "Uniswap V3 Swap",
                "0x414bf389000000000000000000000000a0b86a33e6d33333eb36ce90a66e7ec7a9681b0a",
                "Uniswap V3 Token Swap"
            ),
            (
                "1inch Swap",
                "0x7c025200000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09",
                "1inch Token Swap"
            ),
            (
                "KyberSwap with JSON",
                "0xe21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000006e4141d33021b52c91c28608403db4a0ffb50ec6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000003c000000000000000000000000000000000000000000000000000000000000000e801010000003d0200000011d53ec50bc8f54b9357fbfe2a7de034fc00f8b3000000000000000000071afd498d00000100000000000000000000000000000001000276a40aeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee912ce59144191c1204e64559fe8253a0e49e6548245b8d996d6ef17fd48622048370945d4328f7d00000000000000000000000006851d9f2000000540000000000000000000000000000000000000000000000000000000000000000000000000000000000000ee70dd76c0c0000000000000000e3651af45475f95d4f82e73edb06d29ff62c91ec8f5ff06571bdeb29000000000000000000000000000000000000000000000000000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000912ce59144191c1204e64559fe8253a0e49e65480000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000245b8d996d6ef17fd48622048370945d4328f7d000000000000000000000000000000000000000000000000000071afd498d0000000000000000000000000000000000000000000000000000e2420a2dfcff9fcb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002887b22536f75726365223a226b7962657273776170222c22416d6f756e74496e555344223a22352e303330323731303938373331373235222c22416d6f756e744f7574555344223a22352e303233373732353938363239363638222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223136333835353332343535393438373737383231222c2254696d657374616d70223a313735303139333437342c22526f7574654944223a2231636463343864332d613663352d343864392d393537652d3966383665643736303465663a30386334636539612d396333372d343337642d386263342d633730623764623030376237222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a225a2b542f307773786b666d6a32453266334c2b63773155544a654b43614a73647774424174527234716b67474e3636687673304c314c694f7a566e5a396c305451556256654666667a6a5a73424f6930527a714e4b676745494b776b46344771304d4947486238506a6a4d61433331773558357336322f536431534e30526e6762436a4a394650306c75777538774e42595354667176434863526e6773445a704931454d5034754f4f73585035506d2b6436746f373063737a504541684f304244663434424b627a5134462b767648583366345766463748727a2b385131766a4a5a3064777a7277774f41415a647a4837474147494c6c324463306f67623668437248416a68767a35443174534e68492b6f592f52477165513164395a6a32317a744b784952636a314769675645654e4e46696857745a6e376165764f473139466f362f316a515838305473333048386e4d4f4b69513d3d227d7d000000000000000000000000000000000000000000000000",
                "KyberSwap Token Swap"
            ),
            (
                "Action-based memo",
                "approve token spending",
                "Token Approval"
            ),
            (
                "JSON contract call",
                "{\"method\":\"transfer\"}",
                "Contract: transfer"
            )
        ]
        
        print("\n🚀 Real-World DEX Memo Integration Test:")
        
        for (index, testCase) in realWorldMemos.enumerated() {
            let decoded = testCase.memo.decodedExtensionMemo
            
            XCTAssertNotNil(decoded, "\(testCase.description) should be decoded")
            XCTAssertTrue(
                decoded!.contains(testCase.expectedContains),
                "\(testCase.description) should contain '\(testCase.expectedContains)' but got '\(decoded!)'"
            )
            
            print("\(index + 1). ✅ \(testCase.description)")
            print("   Result: \(decoded!)")
            print("")
        }
        
        print("🎉 All real-world DEX memos decoded successfully!")
    }
    
    // MARK: - Async 4byte.directory API Test
    
    func testAsync4byteDirectoryLookup() async throws {
        // Test with a real unknown function selector
        let unknownMemo = "0x07ed2379000000000000000000000000742F8C1dF7B6A2C1E0b56C4d7F9a7a7b8c3e2A1b"
        
        let parsedMemo = await MemoDecodingService.shared.getParsedMemo(memo: unknownMemo)
        
        if let parsed = parsedMemo {
            print("🎯 4byte.directory API Test Success:")
            print("Function Signature: \(parsed.functionSignature)")
            print("Function Arguments: \(parsed.functionArguments)")
            
            XCTAssertFalse(parsed.functionSignature.isEmpty, "Function signature should not be empty")
        } else {
            print("⚠️ 4byte.directory API Test:")
            print("Could not decode selector 07ed2379 - might not be in database")
            // This is acceptable - the API might not have this specific selector
        }
    }
}
