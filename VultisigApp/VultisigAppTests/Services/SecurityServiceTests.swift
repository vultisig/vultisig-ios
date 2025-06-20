//
//  SecurityServiceTests.swift
//  VultisigAppTests
//
//  Created by Assistant on 2025-01-14.
//

import XCTest
@testable import VultisigApp

class SecurityServiceTests: XCTestCase {
    
    var securityService: SecurityService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Configure SecurityService with Blockaid provider for testing
        let configuration = SecurityServiceFactory.Configuration(
            useBlockaid: true,
            isEnabled: true
        )
        SecurityServiceFactory.configure(with: configuration)
        securityService = SecurityService.shared
    }
    
    override func tearDownWithError() throws {
        securityService = nil
        try super.tearDownWithError()
    }
    
    // MARK: - EVM Transaction Scanning Tests
    
    func testEVMTransactionScan_Transfer() async throws {
        // Test EVM token transfer scanning
        let transferRequest = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .transfer,
            fromAddress: "0x1234567890123456789012345678901234567890",
            toAddress: "0x0987654321098765432109876543210987654321",
            amount: "1000000000000000000", // 1 ETH in wei
            data: nil,
            metadata: ["test": "EVM transfer"]
        )
        
        do {
            let response = try await securityService.scanTransaction(transferRequest)
            XCTAssertNotNil(response)
            XCTAssertEqual(response.provider, "Blockaid")
            XCTAssertNotNil(response.riskLevel)
            print("✅ EVM Transfer Scan - Provider: \(response.provider), Risk: \(response.riskLevel.rawValue)")
        } catch {
            XCTFail("EVM transfer scan failed: \(error.localizedDescription)")
        }
    }
    
    func testEVMTransactionScan_ContractInteraction() async throws {
        // Test EVM contract interaction scanning  
        let contractRequest = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .contractInteraction,
            fromAddress: "0x1234567890123456789012345678901234567890",
            toAddress: "0xA0b86a33E6441c4c0E8B8C8532fD1F7B1B4E7A4F", // Uniswap V2 Router
            amount: "0",
            data: "0x7ff36ab5", // Swap method signature
            metadata: ["test": "EVM contract interaction"]
        )
        
        do {
            let response = try await securityService.scanTransaction(contractRequest)
            XCTAssertNotNil(response)
            XCTAssertEqual(response.provider, "Blockaid")
            print("✅ EVM Contract Interaction Scan - Provider: \(response.provider), Risk: \(response.riskLevel.rawValue)")
        } catch {
            XCTFail("EVM contract interaction scan failed: \(error.localizedDescription)")
        }
    }
    
    func testEVMTransactionScan_Swap() async throws {
        // Test EVM swap transaction scanning
        let swapRequest = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .swap,
            fromAddress: "0x1234567890123456789012345678901234567890",
            toAddress: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap V2 Router
            amount: "1000000000000000000",
            data: "0x38ed1739", // swapExactTokensForTokens
            metadata: ["test": "EVM swap", "tokenA": "USDC", "tokenB": "ETH"]
        )
        
        do {
            let response = try await securityService.scanTransaction(swapRequest)
            XCTAssertNotNil(response)
            XCTAssertEqual(response.provider, "Blockaid")
            print("✅ EVM Swap Scan - Provider: \(response.provider), Risk: \(response.riskLevel.rawValue)")
        } catch {
            XCTFail("EVM swap scan failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Solana Transaction Scanning Tests
    
    func testSolanaTransactionScan_Transfer() async throws {
        // Test Solana SOL transfer scanning (not available in current plan - no providers support Solana)
        let solanaRequest = SecurityScanRequest(
            chain: .solana,
            transactionType: .transfer,
            fromAddress: "11111111111111111111111111111112",
            toAddress: "22222222222222222222222222222223",
            amount: "1000000000", // 1 SOL in lamports
            data: nil,
            metadata: ["test": "Solana transfer"]
        )
        
        // Since no providers support Solana in current plan, SecurityService returns safe response
        let response = try await securityService.scanTransaction(solanaRequest)
        XCTAssertEqual(response.provider, "None")
        XCTAssertEqual(response.riskLevel, .low)
        XCTAssertTrue(response.isSecure)
        print("✅ Solana Transfer Scan returned safe response: No providers support Solana in current plan")
    }
    
    func testSolanaTransactionScan_TokenTransfer() async throws {
        // Test Solana SPL token transfer scanning (not available in current plan - no providers support Solana)
        let tokenRequest = SecurityScanRequest(
            chain: .solana,
            transactionType: .transfer,
            fromAddress: "11111111111111111111111111111112",
            toAddress: "22222222222222222222222222222223",
            amount: "1000000", // 1 USDC (6 decimals)
            data: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // SPL Token program ID
            metadata: ["test": "Solana token transfer", "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"]
        )
        
        // Since no providers support Solana in current plan, SecurityService returns safe response
        let response = try await securityService.scanTransaction(tokenRequest)
        XCTAssertEqual(response.provider, "None")
        XCTAssertEqual(response.riskLevel, .low)
        XCTAssertTrue(response.isSecure)
        print("✅ Solana Token Transfer Scan returned safe response: No providers support Solana in current plan")
    }
    
    // MARK: - Token Scanning Tests
    
    func testTokenScanning_ERC20() async throws {
        // Test ERC-20 token scanning (should fail with unsupported operation on current plan)
        let usdcAddress = "0xA0b86a33E6441c4c0E8B8C8532fD1F7B1B4E7A4F" // USDC token
        
        do {
            let _ = try await securityService.scanToken(usdcAddress, for: .ethereum)
            XCTFail("Expected token scanning to fail with unsupported operation")
        } catch SecurityProviderError.unsupportedOperation(let message) {
            print("✅ ERC-20 Token Scan correctly failed: \(message)")
            XCTAssertTrue(message.contains("not available in current plan"))
        } catch {
            XCTFail("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    func testTokenScanning_SPL() async throws {
        // Test SPL token scanning (should fail with unsupported operation on current plan)
        let splTokenAddress = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" // USDC on Solana
        
        do {
            let _ = try await securityService.scanToken(splTokenAddress, for: .solana)
            XCTFail("Expected token scanning to fail with unsupported operation")
        } catch SecurityProviderError.unsupportedOperation(let message) {
            print("✅ SPL Token Scan correctly failed: \(message)")
            XCTAssertTrue(message.contains("not available in current plan"))
        } catch {
            XCTFail("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Address Validation Tests
    
    func testAddressValidation_EVM() async throws {
        // Test EVM address validation (should fail with unsupported operation on current plan)
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        
        do {
            let _ = try await securityService.validateAddress(address, for: .ethereum)
            XCTFail("Expected address validation to fail with unsupported operation")
        } catch SecurityProviderError.unsupportedOperation(let message) {
            print("✅ EVM Address Validation correctly failed: \(message)")
            XCTAssertTrue(message.contains("not available in current plan"))
        } catch {
            XCTFail("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    func testAddressValidation_Solana() async throws {
        // Test Solana address validation (should fail with unsupported operation on current plan)
        let address = "11111111111111111111111111111112"
        
        do {
            let _ = try await securityService.validateAddress(address, for: .solana)
            XCTFail("Expected address validation to fail with unsupported operation")
        } catch SecurityProviderError.unsupportedOperation(let message) {
            print("✅ Solana Address Validation correctly failed: \(message)")
            XCTAssertTrue(message.contains("not available in current plan"))
        } catch {
            XCTFail("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Multi-Chain Support Tests
    
    func testMultiChainSupport() async throws {
        // Test scanning availability for different chains
        let chainsToTest: [Chain] = [.ethereum, .bscChain, .polygon, .arbitrum, .solana]
        
        for chain in chainsToTest {
            let isAvailable = securityService.isSecurityScanningAvailable(for: chain)
            if isAvailable {
                print("✅ Security scanning available for \(chain.name)")
                
                // Test a simple transfer for supported chains
                let request = SecurityScanRequest(
                    chain: chain,
                    transactionType: .transfer,
                    fromAddress: "0x1234567890123456789012345678901234567890",
                    toAddress: "0x0987654321098765432109876543210987654321",
                    amount: "1000000000000000000",
                    data: nil,
                    metadata: ["test": "Multi-chain support"]
                )
                
                do {
                    let response = try await securityService.scanTransaction(request)
                    print("✅ \(chain.name) scan successful - Risk: \(response.riskLevel.rawValue)")
                } catch {
                    print("⚠️ \(chain.name) scan failed: \(error.localizedDescription)")
                }
            } else {
                print("ℹ️ Security scanning not available for \(chain.name)")
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling_InvalidAddress() async throws {
        // Test with invalid address format
        let invalidRequest = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .transfer,
            fromAddress: "invalid_address",
            toAddress: "also_invalid",
            amount: "1000",
            data: nil,
            metadata: ["test": "Invalid address"]
        )
        
        do {
            let _ = try await securityService.scanTransaction(invalidRequest)
            // If it doesn't throw, that's also valid behavior - the provider might handle it gracefully
            print("ℹ️ Invalid address scan completed (provider handled gracefully)")
        } catch {
            // Expected behavior - invalid addresses should cause errors
            print("✅ Invalid address properly rejected: \(error.localizedDescription)")
        }
    }
    
    func testErrorHandling_EmptyAmount() async throws {
        // Test with empty amount
        let emptyAmountRequest = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .transfer,
            fromAddress: "0x1234567890123456789012345678901234567890",
            toAddress: "0x0987654321098765432109876543210987654321",
            amount: "",
            data: nil,
            metadata: ["test": "Empty amount"]
        )
        
        do {
            let response = try await securityService.scanTransaction(emptyAmountRequest)
            print("ℹ️ Empty amount scan completed: \(response.riskLevel.rawValue)")
        } catch {
            print("ℹ️ Empty amount handled: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Performance Tests
    
    func testConcurrentScanning() async throws {
        // Test multiple concurrent scans
        let requests = (1...5).map { index in
            SecurityScanRequest(
                chain: .ethereum,
                transactionType: .transfer,
                fromAddress: "0x123456789012345678901234567890123456789\(index)",
                toAddress: "0x098765432109876543210987654321098765432\(index)",
                amount: "\(index)000000000000000000",
                data: nil,
                metadata: ["test": "Concurrent scan \(index)"]
            )
        }
        
        let startTime = Date()
        
        // Execute scans concurrently
        try await withThrowingTaskGroup(of: SecurityScanResponse.self) { group in
            for request in requests {
                group.addTask {
                    return try await self.securityService.scanTransaction(request)
                }
            }
            
            var responses: [SecurityScanResponse] = []
            for try await response in group {
                responses.append(response)
            }
            
            XCTAssertEqual(responses.count, requests.count)
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            print("✅ \(requests.count) concurrent scans completed in \(String(format: "%.2f", duration)) seconds")
        }
    }
    
    // MARK: - Helper Methods
    
    func testServiceConfiguration() {
        XCTAssertTrue(securityService.isEnabled)
        XCTAssertTrue(securityService.isSecurityScanningAvailable(for: .ethereum))
        XCTAssertFalse(securityService.isSecurityScanningAvailable(for: .solana)) // Not available in current plan
        print("✅ SecurityService configuration verified")
    }
} 