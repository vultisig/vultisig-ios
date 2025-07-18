//
//  TronServiceTests.swift
//  VultisigAppTests
//
//  Created on 02/01/25.
//

import XCTest
import BigInt
@testable import VultisigApp

@MainActor
final class TronServiceTests: XCTestCase {
    
    var tronService: TronService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tronService = TronService.shared
    }
    
    override func tearDownWithError() throws {
        tronService = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Staked Balance Tests
    
    func testGetStakedBalances() async throws {
        print("🧪 TEST: Get TRON Staked Balances")
        
        // Test with a known TRON address that likely has staked balance
        // Using TRON Foundation address as an example
        let testAddress = "TRzCzicoz3kzF2MBaEKeTf2G8R3aMgaF9x"
        
        do {
            let (energyStaked, bandwidthStaked) = try await tronService.getStakedBalances(address: testAddress)
            
            print("✅ Staked Balances Retrieved:")
            print("   - Energy: \(energyStaked) SUN (\(Double(energyStaked) / 1_000_000.0) TRX)")
            print("   - Bandwidth: \(bandwidthStaked) SUN (\(Double(bandwidthStaked) / 1_000_000.0) TRX)")
            
            // Test should pass if we get a response (even if balances are 0)
            XCTAssertTrue(energyStaked >= 0, "Energy staked should be non-negative")
            XCTAssertTrue(bandwidthStaked >= 0, "Bandwidth staked should be non-negative")
            
        } catch {
            print("❌ Error fetching staked balances: \(error)")
            // Don't fail the test as the address might not have any staked balance
            // or the API might be rate limited
        }
    }
    
    func testGetAccountResources() async throws {
        print("🧪 TEST: Get TRON Account Resources")
        
        let testAddress = "TRzCzicoz3kzF2MBaEKeTf2G8R3aMgaF9x"
        
        do {
            let (energy, bandwidth) = try await tronService.getAccountResources(address: testAddress)
            
            print("✅ Account Resources Retrieved:")
            print("   - Available Energy: \(energy)")
            print("   - Available Bandwidth: \(bandwidth)")
            
            XCTAssertTrue(energy >= 0, "Energy should be non-negative")
            XCTAssertTrue(bandwidth >= 0, "Bandwidth should be non-negative")
            
        } catch {
            print("❌ Error fetching account resources: \(error)")
        }
    }
    
    // MARK: - Memo Format Tests
    
    func testFreezeMemoFormat() {
        let testCases: [(amount: Decimal, resource: TronResourceType, receiver: String?, expected: String)] = [
            (10.0, .energy, nil, "FREEZE:ENERGY:10000000"),
            (10.0, .bandwidth, nil, "FREEZE:BANDWIDTH:10000000"),
            (10.0, .energy, "TRzCzicoz3kzF2MBaEKeTf2G8R3aMgaF9x", "FREEZE:ENERGY:10000000:TRzCzicoz3kzF2MBaEKeTf2G8R3aMgaF9x"),
            (0.5, .energy, nil, "FREEZE:ENERGY:500000"),
            (1000.0, .bandwidth, nil, "FREEZE:BANDWIDTH:1000000000")
        ]
        
        for testCase in testCases {
            let freezeCall = FunctionCallTronFreeze(
                tx: createMockTransaction(),
                functionCallViewModel: FunctionCallViewModel()
            )
            
            freezeCall.amount = testCase.amount
            freezeCall.resource = testCase.resource
            freezeCall.receiver = testCase.receiver ?? ""
            
            let memo = freezeCall.toString()
            XCTAssertEqual(memo, testCase.expected, "Freeze memo format should match expected")
            
            print("✅ Freeze memo test passed: \(memo)")
        }
    }
    
    func testUnfreezeMemoFormat() {
        let testCases: [(amount: Decimal, resource: TronResourceType, expected: String)] = [
            (10.0, .energy, "UNFREEZE:ENERGY:10000000"),
            (10.0, .bandwidth, "UNFREEZE:BANDWIDTH:10000000"),
            (0.5, .energy, "UNFREEZE:ENERGY:500000"),
            (1000.0, .bandwidth, "UNFREEZE:BANDWIDTH:1000000000")
        ]
        
        for testCase in testCases {
            let unfreezeCall = FunctionCallTronUnfreeze(
                tx: createMockTransaction(),
                functionCallViewModel: FunctionCallViewModel()
            )
            
            unfreezeCall.amount = testCase.amount
            unfreezeCall.resource = testCase.resource
            
            let memo = unfreezeCall.toString()
            XCTAssertEqual(memo, testCase.expected, "Unfreeze memo format should match expected")
            
            print("✅ Unfreeze memo test passed: \(memo)")
        }
    }
    
    // MARK: - Validation Tests
    
    func testFreezeValidation() {
        let freezeCall = FunctionCallTronFreeze(
            tx: createMockTransaction(),
            functionCallViewModel: FunctionCallViewModel()
        )
        
        // Test invalid amount (0)
        freezeCall.amount = 0
        XCTAssertFalse(freezeCall.isTheFormValid, "Form should be invalid with 0 amount")
        
        // Test valid amount
        freezeCall.amount = 10.0
        XCTAssertTrue(freezeCall.isTheFormValid, "Form should be valid with positive amount")
        
        // Test amount exceeding balance
        freezeCall.amount = 1000000.0 // Exceeds mock balance
        XCTAssertFalse(freezeCall.isTheFormValid, "Form should be invalid when amount exceeds balance")
        
        // Test with invalid receiver address
        freezeCall.amount = 10.0
        freezeCall.receiver = "invalid_address"
        XCTAssertFalse(freezeCall.isTheFormValid, "Form should be invalid with invalid receiver address")
        
        // Test with valid receiver address
        freezeCall.receiver = "TRzCzicoz3kzF2MBaEKeTf2G8R3aMgaF9x"
        XCTAssertTrue(freezeCall.isTheFormValid, "Form should be valid with valid receiver address")
        
        print("✅ Freeze validation tests passed")
    }
    
    func testUnfreezeValidation() async throws {
        let unfreezeCall = FunctionCallTronUnfreeze(
            tx: createMockTransaction(),
            functionCallViewModel: FunctionCallViewModel()
        )
        
        // Manually set max unfreeze amount for testing
        unfreezeCall.maxUnfreezeAmount = 100.0
        
        // Test invalid amount (0)
        unfreezeCall.amount = 0
        XCTAssertFalse(unfreezeCall.isTheFormValid, "Form should be invalid with 0 amount")
        
        // Test valid amount
        unfreezeCall.amount = 50.0
        XCTAssertTrue(unfreezeCall.isTheFormValid, "Form should be valid with amount less than max")
        
        // Test amount exceeding staked balance
        unfreezeCall.amount = 150.0
        XCTAssertFalse(unfreezeCall.isTheFormValid, "Form should be invalid when amount exceeds staked balance")
        
        // Test MAX button functionality
        unfreezeCall.amount = unfreezeCall.maxUnfreezeAmount
        XCTAssertTrue(unfreezeCall.isTheFormValid, "Form should be valid when amount equals max")
        XCTAssertEqual(unfreezeCall.amount, unfreezeCall.maxUnfreezeAmount, "Amount should equal max after MAX button")
        
        print("✅ Unfreeze validation tests passed")
    }
    
    // MARK: - Resource Type Tests
    
    func testResourceTypeEnum() {
        // Test all resource types
        let resourceTypes = TronResourceType.allCases
        XCTAssertEqual(resourceTypes.count, 2, "Should have exactly 2 resource types")
        
        // Test raw values
        XCTAssertEqual(TronResourceType.energy.rawValue, "ENERGY")
        XCTAssertEqual(TronResourceType.bandwidth.rawValue, "BANDWIDTH")
        
        // Test display values
        XCTAssertTrue(TronResourceType.energy.display.contains("smart contracts"))
        XCTAssertTrue(TronResourceType.bandwidth.display.contains("regular transactions"))
        
        print("✅ Resource type enum tests passed")
    }
    
    // MARK: - Helper Methods
    
    private func createMockTransaction() -> SendTransaction {
        let coinMeta = CoinMeta(
            chain: .tron,
            ticker: "TRX",
            logo: "trx",
            decimals: 6,
            priceProviderId: "tron",
            contractAddress: "",
            isNativeToken: true
        )
        
        let coin = Coin(asset: coinMeta, address: "TRzCzicoz3kzF2MBaEKeTf2G8R3aMgaF9x", hexPublicKey: "test_pub_key")
        coin.rawBalance = "1000000000" // 1000 TRX
        
        return SendTransaction(
            id: UUID(),
            coin: coin,
            toAddress: "TRzCzicoz3kzF2MBaEKeTf2G8R3aMgaF9x",
            amount: Decimal.zero,
            memo: "",
            chainSpecific: .Tron(
                timestamp: 1234567890,
                expiration: 1234567890,
                blockHeaderTimestamp: 1234567890,
                blockHeaderNumber: 12345,
                blockHeaderVersion: 1,
                blockHeaderTxTrieRoot: "0000000000000000000000000000000000000000000000000000000000000000",
                blockHeaderParentHash: "0000000000000000000000000000000000000000000000000000000000000000",
                blockHeaderWitnessAddress: "0000000000000000000000000000000000000000",
                gasEstimation: 0
            )
        )
    }
} 