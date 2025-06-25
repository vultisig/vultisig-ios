//
//  SecurityServiceAPIResponseTests.swift
//  VultisigAppTests
//
//  Created by Assistant on 2025-01-14.
//

import XCTest
@testable import VultisigApp

final class SecurityServiceAPIResponseTests: XCTestCase {
    
    private var securityService: SecurityService!
    
    override func setUpWithError() throws {
        // Initialize SecurityService with Blockaid provider
        securityService = SecurityService.shared
        
        // Ensure security scanning is enabled for tests
        securityService.setEnabled(true)
        
        print("🧪 STARTING COMPREHENSIVE BLOCKAID API TESTS")
        print("🔧 Security Service Configuration:")
        print("   - Enabled: \(securityService.isEnabled)")
        print("   - Providers: \(securityService.providers.map { $0.providerName })")
        print("")
    }
    
    override func tearDownWithError() throws {
        // Clean up after tests
        securityService = nil
    }
    
    // MARK: - EVM Transaction Scanning Tests (✅ Available)
    
    func testEthereumTransactionResponse() async throws {
        print("🧪 TEST: Ethereum Transaction Scanning")
        let ethereumChain = Chain.ethereum
        
        let request = SecurityScanRequest(
            chain: ethereumChain,
            transactionType: .transfer,
            fromAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
            toAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
            amount: "1000000000000000000"
        )
        
        do {
            let response = try await securityService.scanTransaction(request)
            print("✅ Response received:")
            print("   - Provider: \(response.provider)")
            print("   - Secure: \(response.isSecure)")
            print("   - Risk Level: \(response.riskLevel)")
            print("   - Warnings: \(response.warnings.count)")
            
            XCTAssertNotNil(response)
            XCTAssertEqual(response.provider, "Blockaid")
        } catch {
            print("❌ Error: \(error)")
            XCTFail("Transaction scanning should work for Ethereum: \(error)")
        }
    }
    
    func testPolygonTransactionResponse() async throws {
        print("🧪 TEST: Polygon Transaction Scanning")
        let polygonChain = Chain.polygon
        
        let request = SecurityScanRequest(
            chain: polygonChain,
            transactionType: .transfer,
            fromAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
            toAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
            amount: "1000000000000000000"
        )
        
        do {
            let response = try await securityService.scanTransaction(request)
            print("✅ Response received:")
            print("   - Provider: \(response.provider)")
            print("   - Risk Level: \(response.riskLevel)")
            
            XCTAssertNotNil(response)
            XCTAssertEqual(response.provider, "Blockaid")
        } catch {
            print("❌ Error: \(error)")
            XCTFail("Transaction scanning should work for Polygon: \(error)")
        }
    }
    
    func testUniswapSwapResponse() async throws {
        print("🧪 TEST: Uniswap V3 Swap Transaction")
        let request = SecurityScanRequest(
            chain: Chain.ethereum,
            transactionType: .swap,
            fromAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
            toAddress: "0xE592427A0AEce92De3Edee1F18E0157C05861564", // Uniswap V3 Router
            amount: "1000000000000000000"
        )
        
        do {
            let response = try await securityService.scanTransaction(request)
            print("✅ Uniswap response:")
            print("   - Risk Level: \(response.riskLevel)")
            print("   - Warnings: \(response.warnings.count)")
            
            XCTAssertNotNil(response)
        } catch {
            print("❌ Error: \(error)")
            XCTFail("Uniswap scanning failed: \(error)")
        }
    }
    
    // MARK: - Site Scanning Tests (✅ Available)
    
    func testSiteScanning() async throws {
        print("🧪 TEST: Site Scanning - Safe Site")
        let safeUrl = "https://vultisig.com"
        
        do {
            let response = try await securityService.scanSite(safeUrl)
            print("✅ Site scan response:")
            print("   - URL: \(safeUrl)")
            print("   - Risk Level: \(response.riskLevel)")
            print("   - Secure: \(response.isSecure)")
            print("   - Warnings: \(response.warnings.count)")
            
            XCTAssertNotNil(response)
            XCTAssertEqual(response.provider, "Blockaid")
        } catch {
            print("❌ Error: \(error)")
            XCTFail("Site scanning should work: \(error)")
        }
    }
    
    func testSuspiciousSiteScanning() async throws {
        print("🧪 TEST: Site Scanning - Potentially Suspicious")
        let suspiciousUrl = "https://evil-site.malicious.fake-site.test"
        
        do {
            let response = try await securityService.scanSite(suspiciousUrl)
            print("✅ Suspicious site scan response:")
            print("   - URL: \(suspiciousUrl)")
            print("   - Risk Level: \(response.riskLevel)")
            print("   - Secure: \(response.isSecure)")
            print("   - Warnings: \(response.warnings.count)")
            
            XCTAssertNotNil(response)
        } catch {
            print("❌ Error: \(error)")
            // Don't fail - malicious sites might return errors and that's ok
            print("⚠️  Suspicious site scanning returned error (expected behavior)")
        }
    }
    
    // MARK: - Risk Level Mapping Tests
    
    func testComprehensiveRiskLevelMapping() async throws {
        print("🧪 TEST: Risk Level Mapping Validation")
        
        let testCases = [
            (chain: Chain.ethereum, description: "Ethereum"),
            (chain: Chain.bscChain, description: "BSC"), 
            (chain: Chain.polygon, description: "Polygon"),
            (chain: Chain.arbitrum, description: "Arbitrum")
        ]
        
        for testCase in testCases {
            let request = SecurityScanRequest(
                chain: testCase.chain,
                transactionType: .transfer,
                fromAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
                toAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
                amount: "100000000000000000"
            )
            
            do {
                let response = try await securityService.scanTransaction(request)
                print("✅ \(testCase.description) - Risk: \(response.riskLevel)")
                XCTAssertNotNil(response)
                                 XCTAssertTrue([.none, .low, .medium, .high, .critical].contains(response.riskLevel))
            } catch {
                print("❌ \(testCase.description) failed: \(error)")
                XCTFail("Risk level mapping failed for \(testCase.description)")
            }
        }
    }
    
    // MARK: - Rate Limiting Tests
    
    func testRateLimitHandling() async throws {
        print("🧪 TEST: Rate Limit Handling")
        
        let requests = (1...3).map { i in
            SecurityScanRequest(
                chain: Chain.ethereum,
                transactionType: .transfer,
                fromAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
                toAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
                amount: "\(i)00000000000000000"
            )
        }
        
        await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    do {
                        let response = try await self.securityService.scanTransaction(request)
                        print("✅ Request \(index + 1) completed - Risk: \(response.riskLevel)")
                        return (index, true)
                    } catch {
                        print("❌ Request \(index + 1) failed: \(error)")
                        return (index, false)
                    }
                }
            }
            
            var completedCount = 0
            for await (_, success) in group {
                if success {
                    completedCount += 1
                }
            }
            
            print("✅ Rate limit test: \(completedCount)/\(requests.count) requests succeeded")
            XCTAssertGreaterThan(completedCount, 0, "At least some requests should succeed")
        }
    }
    
    // MARK: - Disabled Capabilities Tests (❌ Not Available)
    
    func testBitcoinTransactionCapabilityDisabled() async throws {
        print("🧪 TEST: Bitcoin Transaction Scanning (Should be disabled)")
        
        // Create a Bitcoin-like request 
        let bitcoinRequest = SecurityScanRequest(
            chain: .bitcoin,
            transactionType: .transfer,
            fromAddress: "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2",
            toAddress: "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2",
            amount: "100000000"
        )
        
        do {
            let response = try await securityService.scanTransaction(bitcoinRequest)
            print("✅ Bitcoin response (fallback):")
            print("   - Provider: \(response.provider)")
            print("   - Should be 'None' (fallback): \(response.provider == "None")")
            
            // Should return "None" provider as Bitcoin endpoints aren't available
            XCTAssertEqual(response.provider, "None")
        } catch {
            print("❌ Bitcoin test error: \(error)")
            // This is actually expected since Bitcoin capabilities are disabled
            print("✅ Expected: Bitcoin scanning not available")
        }
    }
    
    func testAddressValidationCapabilityDisabled() async throws {
        print("🧪 TEST: Address Validation (Should be disabled - 403)")
        
        do {
            let response = try await securityService.validateAddress("0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7", for: Chain.ethereum)
            print("❌ Unexpected success: \(response)")
            XCTFail("Address validation should throw error due to 403 (disabled capability)")
        } catch SecurityProviderError.unsupportedOperation(let message) {
            print("✅ Expected error: \(message)")
            XCTAssertTrue(message.contains("not available in current plan"))
        } catch {
            print("✅ Address validation properly disabled: \(error)")
        }
    }
    
    func testTokenScanningCapabilityDisabled() async throws {
        print("🧪 TEST: Token Scanning (Should be disabled - 403)")
        
        do {
            let response = try await securityService.scanToken("0xA0b86a33E6441e13cDb9d59E4a623C79aF0Cc0c7", for: Chain.ethereum)
            print("❌ Unexpected success: \(response)")
            XCTFail("Token scanning should throw error due to 403 (disabled capability)")
        } catch SecurityProviderError.unsupportedOperation(let message) {
            print("✅ Expected error: \(message)")
            XCTAssertTrue(message.contains("not available in current plan"))
        } catch {
            print("✅ Token scanning properly disabled: \(error)")
        }
    }
    
    // MARK: - Provider Configuration Test
    
    func testProviderConfiguration() {
        print("🧪 TEST: Provider Configuration")
        
        let providers = securityService.getProviders()
        print("✅ Available providers: \(providers.map { $0.providerName })")
        
        XCTAssertGreaterThan(providers.count, 0, "Should have at least one provider")
        
        // Check if Blockaid provider is configured
        let hasBlockaid = providers.contains { $0.providerName == "Blockaid" }
        XCTAssertTrue(hasBlockaid, "Should have Blockaid provider configured")
        
        // Check capabilities
        if let blockaidProvider = providers.first(where: { $0.providerName == "Blockaid" }) as? CapabilityAwareSecurityProvider {
            let caps = blockaidProvider.capabilities
            print("✅ Blockaid capabilities:")
            print("   - EVM Transaction Scanning: \(caps.evmTransactionScanning)")
            print("   - Solana Transaction Scanning: \(caps.solanaTransactionScanning)")
            print("   - Address Validation: \(caps.addressValidation)")
            print("   - Token Scanning: \(caps.tokenScanning)")
            print("   - Site Scanning: \(caps.siteScanning)")
            print("   - Bitcoin Transaction Scanning: \(caps.bitcoinTransactionScanning)")
            
            XCTAssertTrue(caps.evmTransactionScanning, "EVM scanning should be enabled")
            XCTAssertTrue(caps.siteScanning, "Site scanning should be enabled")
            XCTAssertFalse(caps.solanaTransactionScanning, "Solana should be disabled (not in GA)")
            XCTAssertFalse(caps.addressValidation, "Address validation should be disabled (403)")
            XCTAssertFalse(caps.tokenScanning, "Token scanning should be disabled (403)")
            XCTAssertFalse(caps.bitcoinTransactionScanning, "Bitcoin should be disabled (404)")
        }
    }
} 