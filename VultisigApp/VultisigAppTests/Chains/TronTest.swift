//
//  TronTest.swift
//  VultisigAppTests
//
//  Created on 02/01/25.
//

import XCTest
import WalletCore
@testable import VultisigApp

final class TronTest: XCTestCase {
    
    // MARK: - Freeze Transaction Tests
    
    func testFreezeTransactionParsing() throws {
        // Test freeze memo parsing
        let freezeMemos = [
            "FREEZE:ENERGY:10000000",
            "FREEZE:BANDWIDTH:50000000",
            "FREEZE:ENERGY:10000000:TRzCzicoz3kzF2MBaEKeTf2G8R3aMgaF9x"
        ]
        
        for memo in freezeMemos {
            let components = memo.split(separator: ":")
            
            XCTAssertTrue(components.count >= 3, "Freeze memo should have at least 3 components")
            XCTAssertEqual(components[0], "FREEZE", "First component should be FREEZE")
            XCTAssertTrue(["ENERGY", "BANDWIDTH"].contains(String(components[1])), "Second component should be valid resource type")
            
            let amount = Int64(components[2])
            XCTAssertNotNil(amount, "Third component should be valid amount")
            
            if components.count > 3 {
                let receiver = String(components[3])
                XCTAssertTrue(receiver.hasPrefix("T"), "Receiver should be valid TRON address")
                XCTAssertEqual(receiver.count, 34, "TRON address should be 34 characters")
            }
            
            print("✅ Freeze memo parsed successfully: \(memo)")
        }
    }
    
    func testUnfreezeTransactionParsing() throws {
        // Test unfreeze memo parsing
        let unfreezeMemos = [
            "UNFREEZE:ENERGY:10000000",
            "UNFREEZE:BANDWIDTH:50000000"
        ]
        
        for memo in unfreezeMemos {
            let components = memo.split(separator: ":")
            
            XCTAssertEqual(components.count, 3, "Unfreeze memo should have exactly 3 components")
            XCTAssertEqual(components[0], "UNFREEZE", "First component should be UNFREEZE")
            XCTAssertTrue(["ENERGY", "BANDWIDTH"].contains(String(components[1])), "Second component should be valid resource type")
            
            let amount = Int64(components[2])
            XCTAssertNotNil(amount, "Third component should be valid amount")
            
            print("✅ Unfreeze memo parsed successfully: \(memo)")
        }
    }
    
    // MARK: - Amount Conversion Tests
    
    func testTRXToSUNConversion() {
        let testCases: [(trx: Decimal, expectedSun: Int64)] = [
            (1.0, 1_000_000),
            (0.1, 100_000),
            (0.01, 10_000),
            (0.001, 1_000),
            (0.000001, 1),
            (1000.0, 1_000_000_000),
            (0.123456, 123_456)
        ]
        
        for testCase in testCases {
            let sunAmount = NSDecimalNumber(decimal: testCase.trx * Decimal(1_000_000)).int64Value
            XCTAssertEqual(sunAmount, testCase.expectedSun, "\(testCase.trx) TRX should equal \(testCase.expectedSun) SUN")
            
            // Test reverse conversion
            let trxAmount = Decimal(sunAmount) / Decimal(1_000_000)
            XCTAssertEqual(trxAmount, testCase.trx, "\(sunAmount) SUN should equal \(testCase.trx) TRX")
        }
        
        print("✅ TRX to SUN conversion tests passed")
    }
    
    // MARK: - Resource Estimation Tests
    
    func testFreezeResourceEstimation() {
        let freezeCall = FunctionCallTronFreeze(
            tx: createMockTransaction(),
            functionCallViewModel: FunctionCallViewModel()
        )
        
        // Test energy estimation
        freezeCall.resource = .energy
        freezeCall.amount = 100.0
        let energyEstimate = freezeCall.estimatedResources
        XCTAssertTrue(energyEstimate.contains("Energy/day"), "Should show energy estimate")
        XCTAssertTrue(energyEstimate.contains("3000"), "100 TRX should give ~3000 energy/day")
        
        // Test bandwidth estimation
        freezeCall.resource = .bandwidth
        freezeCall.amount = 100.0
        let bandwidthEstimate = freezeCall.estimatedResources
        XCTAssertTrue(bandwidthEstimate.contains("Bandwidth/day"), "Should show bandwidth estimate")
        XCTAssertTrue(bandwidthEstimate.contains("20000"), "100 TRX should give ~20000 bandwidth/day")
        
        print("✅ Resource estimation tests passed")
    }
    
    // MARK: - Function Call Instance Tests
    
    func testFunctionCallInstanceForTRON() {
        let vault = Vault(localPartyID: "test-party")
        let coin = createMockCoin()
        let tx = createMockTransaction()
        let functionCallViewModel = FunctionCallViewModel()
        
        // Test default function call for TRON
        let defaultInstance = FunctionCallInstance.getDefault(for: coin, tx: tx, functionCallViewModel: functionCallViewModel, vault: vault)
        
        switch defaultInstance {
        case .tronFreeze(_):
            XCTAssertTrue(true, "Default TRON function call should be freeze")
        default:
            XCTFail("Default TRON function call should be tronFreeze")
        }
        
        // Test function call types available for TRON
        let availableTypes = FunctionCallType.getCases(for: coin)
        XCTAssertEqual(availableTypes.count, 2, "TRON should have 2 function call types")
        XCTAssertTrue(availableTypes.contains(.tronFreeze), "TRON should have freeze function")
        XCTAssertTrue(availableTypes.contains(.tronUnfreeze), "TRON should have unfreeze function")
        
        print("✅ Function call instance tests passed")
    }
    
    // MARK: - Transaction Amount Tests
    
    func testTransactionAmountForFreeze() {
        let freezeCall = FunctionCallTronFreeze(
            tx: createMockTransaction(),
            functionCallViewModel: FunctionCallViewModel()
        )
        freezeCall.amount = 100.0
        
        let instance = FunctionCallInstance.tronFreeze(freezeCall)
        XCTAssertEqual(instance.amount, 100.0, "Freeze transaction should include the amount")
    }
    
    func testTransactionAmountForUnfreeze() {
        let unfreezeCall = FunctionCallTronUnfreeze(
            tx: createMockTransaction(),
            functionCallViewModel: FunctionCallViewModel()
        )
        unfreezeCall.amount = 100.0
        
        let instance = FunctionCallInstance.tronUnfreeze(unfreezeCall)
        XCTAssertEqual(instance.amount, 0, "Unfreeze transaction should have 0 amount (amount is in memo)")
    }
    
    // MARK: - Helper Methods
    
    private func createMockCoin() -> Coin {
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
        return coin
    }
    
    private func createMockTransaction() -> SendTransaction {
        let coin = createMockCoin()
        
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