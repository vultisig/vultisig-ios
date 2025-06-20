//
//  SecurityServiceAPIResponseTests.swift
//  VultisigAppTests
//
//  Created by Assistant on 2025-01-14.
//

import XCTest
@testable import VultisigApp

class SecurityServiceAPIResponseTests: XCTestCase {
    
    var securityService: SecurityService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
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
    
    // MARK: - Working API Response Tests
    
    func testEthereumTransactionResponse() async throws {
        print("\n🧪 TESTING: Ethereum Transaction Scanning")
        
        let request = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .transfer,
            fromAddress: "0x742d35Cc6634C0532925a3b8D2FD0E7ed30C7D6B",
            toAddress: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", // WBTC contract
            amount: "1000000000000000000", // 1 ETH in wei
            data: nil,
            metadata: ["test": "Real Ethereum transfer"]
        )
        
        do {
            let response = try await securityService.scanTransaction(request)
            
            print("✅ SUCCESS: Received response from Blockaid")
            print("📊 Provider: \(response.provider)")
            print("🔒 Is Secure: \(response.isSecure)")
            print("⚠️ Risk Level: \(response.riskLevel.rawValue)")
            print("🚨 Warnings Count: \(response.warnings.count)")
            print("📝 Recommendations Count: \(response.recommendations.count)")
            
            if let metadata = response.metadata {
                print("📄 Metadata:")
                for (key, value) in metadata {
                    print("   - \(key): \(value)")
                }
            }
            
            if !response.warnings.isEmpty {
                print("⚠️ Warnings:")
                for warning in response.warnings {
                    print("   - Type: \(warning.type.rawValue)")
                    print("   - Severity: \(warning.severity.rawValue)")
                    print("   - Message: \(warning.message)")
                    if let details = warning.details {
                        print("   - Details: \(details)")
                    }
                }
            }
            
            if !response.recommendations.isEmpty {
                print("📋 Recommendations:")
                for recommendation in response.recommendations {
                    print("   - \(recommendation)")
                }
            }
            
            // Verify basic response structure
            XCTAssertEqual(response.provider, "Blockaid")
            XCTAssertNotNil(response.riskLevel)
            
        } catch {
            XCTFail("Ethereum transaction scan failed: \(error.localizedDescription)")
        }
    }
    
    func testUniswapSwapResponse() async throws {
        print("\n🧪 TESTING: Basic Contract Interaction")
        
        let request = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .transfer,
            fromAddress: "0x742d35Cc6634C0532925a3b8D2FD0E7ed30C7D6B",
            toAddress: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap V2 Router
            amount: "1000000000000000000",
            data: "0x",
            metadata: ["test": "Basic contract interaction"]
        )
        
        do {
            let response = try await securityService.scanTransaction(request)
            
            print("✅ SUCCESS: Basic contract interaction scan completed")
            print("📊 Provider: \(response.provider)")
            print("🔒 Is Secure: \(response.isSecure)")
            print("⚠️ Risk Level: \(response.riskLevel.rawValue)")
            print("🚨 Warnings Count: \(response.warnings.count)")
            
            if let metadata = response.metadata {
                print("📄 Blockaid Metadata:")
                for (key, value) in metadata {
                    print("   - \(key): \(value)")
                }
            }
            
            XCTAssertEqual(response.provider, "Blockaid")
            XCTAssertNotNil(response.riskLevel)
            
        } catch {
            XCTFail("Basic contract interaction scan failed: \(error.localizedDescription)")
        }
    }
    
    func testBSCTransactionResponse() async throws {
        print("\n🧪 TESTING: BSC Transaction Scanning")
        
        let request = SecurityScanRequest(
            chain: .bscChain,
            transactionType: .transfer,
            fromAddress: "0x742d35Cc6634C0532925a3b8D2FD0E7ed30C7D6B",
            toAddress: "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", // BUSD contract
            amount: "1000000000000000000",
            data: nil,
            metadata: ["test": "BSC Chain transfer"]
        )
        
        do {
            let response = try await securityService.scanTransaction(request)
            
            print("✅ SUCCESS: BSC transaction scan completed")
            print("📊 Risk Level: \(response.riskLevel.rawValue)")
            print("🚨 Has Warnings: \(response.hasWarnings)")
            
            XCTAssertEqual(response.provider, "Blockaid")
            XCTAssertNotNil(response.riskLevel)
            
        } catch {
            XCTFail("BSC transaction scan failed: \(error.localizedDescription)")
        }
    }
    
    func testPolygonTransactionResponse() async throws {
        print("\n🧪 TESTING: Polygon Transaction Scanning")
        
        let request = SecurityScanRequest(
            chain: .polygon,
            transactionType: .transfer,
            fromAddress: "0x742d35Cc6634C0532925a3b8D2FD0E7ed30C7D6B",
            toAddress: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC on Polygon
            amount: "1000000000000000000",
            data: nil,
            metadata: ["test": "Polygon transfer"]
        )
        
        do {
            let response = try await securityService.scanTransaction(request)
            
            print("✅ SUCCESS: Polygon transaction scan completed")
            print("📊 Risk Level: \(response.riskLevel.rawValue)")
            
            XCTAssertEqual(response.provider, "Blockaid")
            XCTAssertNotNil(response.riskLevel)
            
        } catch {
            XCTFail("Polygon transaction scan failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Error Response Tests (403 endpoints)
    
    func testTokenScanningResponse() async throws {
        print("\n🧪 TESTING: Token Scanning (Expected Unsupported Operation)")
        
        let tokenAddress = "0xA0b86a33E6441c4c0E8B8C8532fD1F7B1B4E7A4F" // Random ERC-20
        
        do {
            let _ = try await securityService.scanToken(tokenAddress, for: .ethereum)
            XCTFail("Expected token scanning to fail with unsupported operation")
            
        } catch SecurityProviderError.unsupportedOperation(let message) {
            print("⚠️ EXPECTED FAILURE: Token scan failed with: \(message)")
            XCTAssertTrue(message.contains("not available in current plan"))
            print("✅ Correct unsupported operation error received")
            
        } catch {
            XCTFail("Expected SecurityProviderError.unsupportedOperation, got: \(error.localizedDescription)")
        }
    }
    
    func testAddressValidationResponse() async throws {
        print("\n🧪 TESTING: Address Validation (Expected Unsupported Operation)")
        
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" // vitalik.eth
        
        do {
            let _ = try await securityService.validateAddress(address, for: .ethereum)
            XCTFail("Expected address validation to fail with unsupported operation")
            
        } catch SecurityProviderError.unsupportedOperation(let message) {
            print("⚠️ EXPECTED FAILURE: Address validation failed with: \(message)")
            XCTAssertTrue(message.contains("not available in current plan"))
            print("✅ Correct unsupported operation error received")
            
        } catch {
            XCTFail("Expected SecurityProviderError.unsupportedOperation, got: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Performance and Stress Tests
    
    func testMultipleEVMChainResponses() async throws {
        print("\n🧪 TESTING: Multiple EVM Chains Performance")
        
        let chains: [Chain] = [.ethereum, .bscChain, .polygon, .arbitrum]
        let startTime = Date()
        
        for chain in chains {
            let request = SecurityScanRequest(
                chain: chain,
                transactionType: .transfer,
                fromAddress: "0x742d35Cc6634C0532925a3b8D2FD0E7ed30C7D6B",
                toAddress: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
                amount: "1000000000000000000",
                data: nil,
                metadata: ["test": "Multi-chain test", "chain": chain.name]
            )
            
            do {
                let response = try await securityService.scanTransaction(request)
                print("✅ \(chain.name): Risk \(response.riskLevel.rawValue)")
                
                XCTAssertEqual(response.provider, "Blockaid")
                XCTAssertNotNil(response.riskLevel)
                
            } catch {
                XCTFail("\(chain.name) scan failed: \(error.localizedDescription)")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        print("⏱️ Total time for \(chains.count) chains: \(String(format: "%.2f", duration)) seconds")
        print("📊 Average time per chain: \(String(format: "%.2f", duration / Double(chains.count))) seconds")
    }
    
    func testRealWorldContractInteraction() async throws {
        print("\n🧪 TESTING: Real-World Contract Interaction")
        
        // Test interaction with a real DeFi contract (Compound)
        let request = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .contractInteraction,
            fromAddress: "0x742d35Cc6634C0532925a3b8D2FD0E7ed30C7D6B",
            toAddress: "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", // Compound Comptroller
            amount: "0",
            data: "0x4ef4c3e1000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005d3a536e4d6dbd6114cc1ead35777bab948e3643",
            metadata: ["test": "Compound interaction", "protocol": "compound"]
        )
        
        do {
            let response = try await securityService.scanTransaction(request)
            
            print("✅ SUCCESS: Compound contract interaction scan completed")
            print("📊 Risk Level: \(response.riskLevel.rawValue)")
            print("🚨 Warnings Count: \(response.warnings.count)")
            
            if !response.warnings.isEmpty {
                print("⚠️ DeFi Warnings Found:")
                for warning in response.warnings {
                    print("   - \(warning.type.rawValue): \(warning.message)")
                }
            }
            
            XCTAssertEqual(response.provider, "Blockaid")
            
        } catch {
            XCTFail("Compound contract interaction scan failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Response Structure Validation
    
    func testResponseStructureValidation() async throws {
        print("\n🧪 TESTING: Response Structure Validation")
        
        let request = SecurityScanRequest(
            chain: .ethereum,
            transactionType: .transfer,
            fromAddress: "0x742d35Cc6634C0532925a3b8D2FD0E7ed30C7D6B",
            toAddress: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
            amount: "1000000000000000000",
            data: nil,
            metadata: nil
        )
        
        let response = try await securityService.scanTransaction(request)
        
        // Validate all required fields are present
        XCTAssertFalse(response.provider.isEmpty, "Provider should not be empty")
        XCTAssertNotNil(response.riskLevel, "Risk level should be present")
        XCTAssertNotNil(response.warnings, "Warnings array should be present")
        XCTAssertNotNil(response.recommendations, "Recommendations array should be present")
        
        // Validate risk level is valid
        let validRiskLevels: [SecurityRiskLevel] = [.low, .medium, .high, .critical]
        XCTAssertTrue(validRiskLevels.contains(response.riskLevel), "Risk level should be valid")
        
        // Validate metadata structure if present
        if let metadata = response.metadata {
            print("📄 Metadata validation:")
            for (key, value) in metadata {
                print("   - \(key): \(value)")
                XCTAssertFalse(key.isEmpty, "Metadata keys should not be empty")
            }
        }
        
        print("✅ Response structure validation passed")
    }
} 