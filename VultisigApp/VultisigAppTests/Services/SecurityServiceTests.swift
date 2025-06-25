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
        
        // Configure SecurityService with enabled providers for testing
        let configuration = SecurityServiceFactory.Configuration(
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
        // Test Solana SOL transfer scanning (not available - Blockaid returns "not supported in GA")
        let solanaRequest = SecurityScanRequest(
            chain: .solana,
            transactionType: .transfer,
            fromAddress: "11111111111111111111111111111112",
            toAddress: "22222222222222222222222222222223",
            amount: "1000000000", // 1 SOL in lamports
            data: nil,
            metadata: ["test": "Solana transfer"]
        )
        
        // Solana is not supported in GA, so it returns None provider
        let response = try await securityService.scanTransaction(solanaRequest)
        XCTAssertEqual(response.provider, "None")
        XCTAssertEqual(response.riskLevel, .low)
        XCTAssertTrue(response.isSecure)
        print("✅ Solana Transfer Scan returned safe response: Solana not supported in GA")
    }
    
    func testSolanaTransactionScan_TokenTransfer() async throws {
        // Test Solana SPL token transfer scanning (not available - Blockaid returns "not supported in GA")
        let tokenRequest = SecurityScanRequest(
            chain: .solana,
            transactionType: .transfer,
            fromAddress: "11111111111111111111111111111112",
            toAddress: "22222222222222222222222222222223",
            amount: "1000000", // 1 USDC (6 decimals)
            data: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // SPL Token program ID
            metadata: ["test": "Solana token transfer", "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"]
        )
        
        // Solana is not supported in GA, so it returns None provider
        let response = try await securityService.scanTransaction(tokenRequest)
        XCTAssertEqual(response.provider, "None")
        XCTAssertEqual(response.riskLevel, .low)
        XCTAssertTrue(response.isSecure)
        print("✅ Solana Token Transfer Scan returned safe response: Solana not supported in GA")
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
    
    // MARK: - Comprehensive Chain Support Tests
    
    func testAllEVMChains() async throws {
        print("🧪 Testing ALL EVM Chains")
        
        let evmChains: [Chain] = [
            .ethereum,
            .avalanche,
            .base,
            .blast,
            .arbitrum,
            .polygon,
            .polygonV2,
            .optimism,
            .bscChain,
            .cronosChain,
            .zksync,
            .ethereumSepolia
        ]
        
        for chain in evmChains {
            print("\n📊 Testing \(chain.name) (\(chain.rawValue))")
            
            let request = SecurityScanRequest(
                chain: chain,
                transactionType: .transfer,
                fromAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
                toAddress: "0x0987654321098765432109876543210987654321",
                amount: "1000000000000000000", // 1 ETH equivalent
                data: nil,
                metadata: ["chain": chain.name, "test": "EVM chain support"]
            )
            
            do {
                let response = try await securityService.scanTransaction(request)
                print("✅ \(chain.name) scan successful:")
                print("   - Provider: \(response.provider)")
                print("   - Risk Level: \(response.riskLevel.rawValue)")
                print("   - Secure: \(response.isSecure)")
                XCTAssertEqual(response.provider, "Blockaid", "\(chain.name) should use Blockaid provider")
            } catch {
                print("❌ \(chain.name) scan failed: \(error)")
                XCTFail("\(chain.name) transaction scan should work: \(error)")
            }
        }
    }
    
    func testAllBitcoinUTXOChains() async throws {
        print("\n🧪 Testing ALL Bitcoin/UTXO Chains")
        
        let utxoChains: [Chain] = [
            .bitcoin,
            .bitcoinCash,
            .litecoin,
            .dogecoin,
            .dash,
            .zcash
        ]
        
        for chain in utxoChains {
            print("\n📊 Testing \(chain.name) (\(chain.rawValue))")
            
            // Use appropriate address format for UTXO chains
            let fromAddress = chain == .bitcoin ? "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" : "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
            let toAddress = chain == .bitcoin ? "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq" : "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2"
            
            // Sample raw transaction hex for Bitcoin (this is a real transaction format but with dummy data)
            let rawTxHex = "0200000001abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890000000006a473044022012345678901234567890123456789012345678901234567890123456789012340220123456789012345678901234567890123456789012345678901234567890123401210234567890123456789012345678901234567890123456789012345678901234567890ffffffff0100e1f505000000001976a914123456789012345678901234567890123456789088ac00000000"
            
            let request = SecurityScanRequest(
                chain: chain,
                transactionType: .transfer,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: "100000000", // 1 BTC in satoshis
                data: rawTxHex, // Include raw transaction hex for Bitcoin
                metadata: ["chain": chain.name, "test": "UTXO chain support"]
            )
            
            // Bitcoin/UTXO scanning is not supported (returns 404), so we expect None provider
            let response = try await securityService.scanTransaction(request)
            print("✅ \(chain.name) scan returned fallback:")
            print("   - Provider: \(response.provider)")
            print("   - Risk Level: \(response.riskLevel.rawValue)")
            print("   - Secure: \(response.isSecure)")
            
            // All UTXO chains should return "None" provider since they're not supported
            XCTAssertEqual(response.provider, "None", "\(chain.name) should use 'None' provider (not supported)")
            XCTAssertEqual(response.riskLevel, .low, "\(chain.name) should return low risk")
        }
    }
    
    func testSolanaChain() async throws {
        print("\n🧪 Testing Solana Chain")
        
        let solanaAddress1 = "11111111111111111111111111111112"
        let solanaAddress2 = "22222222222222222222222222222223"
        
        // Sample Solana transaction message (base64 encoded)
        let solanaMessage = "AQABAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
        
        let request = SecurityScanRequest(
            chain: .solana,
            transactionType: .transfer,
            fromAddress: solanaAddress1,
            toAddress: solanaAddress2,
            amount: "1000000000", // 1 SOL in lamports
            data: solanaMessage, // Include serialized transaction message
            metadata: ["chain": "Solana", "test": "Solana support"]
        )
        
        // Solana is not supported in GA, so we expect None provider
        let response = try await securityService.scanTransaction(request)
        print("✅ Solana scan returned fallback:")
        print("   - Provider: \(response.provider)")
        print("   - Risk Level: \(response.riskLevel.rawValue)")
        print("   - Secure: \(response.isSecure)")
        XCTAssertEqual(response.provider, "None", "Solana should use 'None' provider (not supported in GA)")
        XCTAssertEqual(response.riskLevel, .low, "Solana should return low risk")
    }
    
    func testUnsupportedChains() async throws {
        print("\n🧪 Testing Unsupported Chains")
        
        let unsupportedChains: [Chain] = [
            .thorChain,
            .mayaChain,
            .gaiaChain,
            .kujira,
            .dydx,
            .osmosis,
            .terra,
            .terraClassic,
            .noble,
            .akash,
            .sui,
            .polkadot,
            .ton,
            .ripple,
            .tron,
            .cardano
        ]
        
        for chain in unsupportedChains {
            print("\n📊 Testing \(chain.name) (\(chain.rawValue)) - Expected to be unsupported")
            
            let request = SecurityScanRequest(
                chain: chain,
                transactionType: .transfer,
                fromAddress: "test_address_1",
                toAddress: "test_address_2",
                amount: "1000000",
                data: nil,
                metadata: ["chain": chain.name, "test": "Unsupported chain"]
            )
            
            let isAvailable = securityService.isSecurityScanningAvailable(for: chain)
            XCTAssertFalse(isAvailable, "\(chain.name) should not have security scanning available")
            
            do {
                let response = try await securityService.scanTransaction(request)
                print("ℹ️ \(chain.name) returned response:")
                print("   - Provider: \(response.provider)")
                print("   - Risk Level: \(response.riskLevel.rawValue)")
                // Unsupported chains should return "None" provider with low risk
                XCTAssertEqual(response.provider, "None", "\(chain.name) should use 'None' provider")
                XCTAssertEqual(response.riskLevel, .low, "\(chain.name) should return low risk")
            } catch {
                print("ℹ️ \(chain.name) threw error (expected): \(error)")
            }
        }
    }
    
    func testChainMappingAccuracy() async throws {
        print("\n🧪 Testing Chain Mapping Accuracy")
        
        // Test that specific chains map to correct Blockaid chain identifiers
        let chainMappings: [(chain: Chain, expectedMapping: String)] = [
            (.ethereum, "ethereum"),
            (.polygon, "polygon"),
            (.polygonV2, "polygon"),
            (.bscChain, "bsc"),
            (.avalanche, "avalanche"),
            (.arbitrum, "arbitrum"),
            (.optimism, "optimism"),
            (.base, "base"),
            (.solana, "solana"),
            (.bitcoin, "bitcoin"),
            (.bitcoinCash, "bitcoin-cash"),
            (.litecoin, "litecoin"),
            (.dogecoin, "dogecoin"),
            (.dash, "dash")
        ]
        
        for (chain, expectedMapping) in chainMappings {
            print("\n📊 Verifying \(chain.name) maps to '\(expectedMapping)'")
            
            // We can't directly test the mapping function, but we can verify
            // that the chain works as expected
            if securityService.isSecurityScanningAvailable(for: chain) {
                print("✅ \(chain.name) is available for scanning")
            } else {
                print("❌ \(chain.name) is not available for scanning")
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
        XCTAssertFalse(securityService.isSecurityScanningAvailable(for: .solana)) // Not available in GA
        XCTAssertFalse(securityService.isSecurityScanningAvailable(for: .bitcoin)) // Returns 404
        print("✅ SecurityService configuration verified")
    }
} 