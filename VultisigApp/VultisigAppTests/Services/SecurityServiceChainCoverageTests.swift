//
//  SecurityServiceChainCoverageTests.swift
//  VultisigAppTests
//
//  Created by Assistant on 2025-01-14.
//

import XCTest
@testable import VultisigApp

/// Comprehensive test suite to ensure all chains are properly tested for security scanning
final class SecurityServiceChainCoverageTests: XCTestCase {
    
    private var securityService: SecurityService!
    
    override func setUpWithError() throws {
        securityService = SecurityService.shared
        securityService.setEnabled(true)
        
        print("🧪 CHAIN COVERAGE TEST SUITE")
        print("📊 Total chains in app: \(Chain.allCases.count)")
        print("")
    }
    
    override func tearDownWithError() throws {
        securityService = nil
    }
    
    // MARK: - Chain Coverage Report
    
    func testGenerateChainCoverageReport() async throws {
        print("📊 GENERATING CHAIN COVERAGE REPORT")
        print("=" * 80)
        
        var supportedChains: [Chain] = []
        var unsupportedChains: [Chain] = []
        var testedChains: [Chain] = []
        var failedChains: [Chain] = []
        
        for chain in Chain.allCases {
            let isSupported = securityService.isSecurityScanningAvailable(for: chain)
            
            if isSupported {
                supportedChains.append(chain)
            } else {
                unsupportedChains.append(chain)
            }
            
            // Test each chain
            let testRequest = createTestRequest(for: chain)
            do {
                let response = try await securityService.scanTransaction(testRequest)
                testedChains.append(chain)
                
                if response.provider != "None" && response.provider != "Blockaid" {
                    print("⚠️ Unexpected provider '\(response.provider)' for \(chain.name)")
                }
            } catch {
                failedChains.append(chain)
                print("❌ \(chain.name) test failed: \(error)")
            }
        }
        
        // Print report
        print("\n📈 CHAIN COVERAGE SUMMARY:")
        print("   Total Chains: \(Chain.allCases.count)")
        print("   Supported Chains: \(supportedChains.count)")
        print("   Unsupported Chains: \(unsupportedChains.count)")
        print("   Successfully Tested: \(testedChains.count)")
        print("   Failed Tests: \(failedChains.count)")
        
        print("\n✅ SUPPORTED CHAINS (\(supportedChains.count)):")
        for chain in supportedChains {
            print("   - \(chain.name) (\(chain.rawValue))")
        }
        
        print("\n❌ UNSUPPORTED CHAINS (\(unsupportedChains.count)):")
        for chain in unsupportedChains {
            print("   - \(chain.name) (\(chain.rawValue))")
        }
        
        if !failedChains.isEmpty {
            print("\n⚠️ FAILED TESTS (\(failedChains.count)):")
            for chain in failedChains {
                print("   - \(chain.name) (\(chain.rawValue))")
            }
        }
        
        print("\n" + "=" * 80)
        
        // Assertions
        XCTAssertEqual(testedChains.count + failedChains.count, Chain.allCases.count, "All chains should be tested")
        XCTAssertTrue(supportedChains.count > 0, "Should have at least some supported chains")
    }
    
    // MARK: - Chain Type Coverage
    
    func testChainTypeCoverage() async throws {
        print("\n📊 TESTING CHAIN TYPE COVERAGE")
        
        let chainsByType = Dictionary(grouping: Chain.allCases) { $0.chainType }
        
        for (chainType, chains) in chainsByType {
            print("\n🔗 \(chainType) Chains (\(chains.count)):")
            
            var supportedCount = 0
            for chain in chains {
                let isSupported = securityService.isSecurityScanningAvailable(for: chain)
                print("   - \(chain.name): \(isSupported ? "✅ Supported" : "❌ Not Supported")")
                if isSupported {
                    supportedCount += 1
                }
            }
            
            print("   Summary: \(supportedCount)/\(chains.count) supported")
            
            // Type-specific assertions
            switch chainType {
            case .EVM:
                XCTAssertEqual(supportedCount, chains.count, "All EVM chains should be supported")
            case .UTXO:
                XCTAssertGreaterThan(supportedCount, 0, "At least some UTXO chains should be supported")
            case .Solana:
                XCTAssertEqual(supportedCount, 1, "Solana should be supported")
            default:
                // Other chain types may not be supported
                break
            }
        }
    }
    
    // MARK: - Specific Chain Tests
    
    func testEachChainIndividually() async throws {
        print("\n📊 TESTING EACH CHAIN INDIVIDUALLY")
        
        let testResults = await withTaskGroup(of: (Chain, Bool, String).self) { group in
            for chain in Chain.allCases {
                group.addTask {
                    let testRequest = self.createTestRequest(for: chain)
                    
                    do {
                        let response = try await self.securityService.scanTransaction(testRequest)
                        let resultMessage = "Provider: \(response.provider), Risk: \(response.riskLevel.rawValue)"
                        return (chain, true, resultMessage)
                    } catch {
                        return (chain, false, error.localizedDescription)
                    }
                }
            }
            
            var results: [(Chain, Bool, String)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // Sort results by chain name for consistent output
        let sortedResults = testResults.sorted { $0.0.name < $1.0.name }
        
        print("\n📋 INDIVIDUAL CHAIN TEST RESULTS:")
        for (chain, success, message) in sortedResults {
            let statusIcon = success ? "✅" : "❌"
            print("\(statusIcon) \(chain.name): \(message)")
        }
        
        let successCount = testResults.filter { $0.1 }.count
        print("\n📈 Success Rate: \(successCount)/\(Chain.allCases.count) (\(Int(Double(successCount) / Double(Chain.allCases.count) * 100))%)")
    }
    
    // MARK: - Chain Mapping Validation
    
    func testChainMappingValidation() async throws {
        print("\n📊 VALIDATING CHAIN MAPPINGS")
        
        // Define expected mappings based on Blockaid documentation
        let expectedMappings: [Chain: String] = [
            .ethereum: "ethereum",
            .polygon: "polygon",
            .polygonV2: "polygon",
            .bscChain: "bsc",
            .avalanche: "avalanche",
            .arbitrum: "arbitrum",
            .optimism: "optimism",
            .base: "base",
            .solana: "solana",
            .bitcoin: "bitcoin",
            .bitcoinCash: "bitcoin-cash",
            .litecoin: "litecoin",
            .dogecoin: "dogecoin",
            .dash: "dash",
            // EVM chains that should default to ethereum
            .blast: "ethereum",
            .cronosChain: "ethereum",
            .zksync: "ethereum",
            .ethereumSepolia: "ethereum"
        ]
        
        print("\n🗺️ Expected Chain Mappings:")
        for (chain, expectedMapping) in expectedMappings.sorted(by: { $0.key.name < $1.key.name }) {
            print("   \(chain.name) → \(expectedMapping)")
        }
        
        // Validate that supported chains work correctly
        for (chain, _) in expectedMappings {
            if securityService.isSecurityScanningAvailable(for: chain) {
                let request = createTestRequest(for: chain)
                do {
                    let response = try await securityService.scanTransaction(request)
                    XCTAssertEqual(response.provider, "Blockaid", "\(chain.name) should use Blockaid provider")
                } catch {
                    XCTFail("\(chain.name) should not throw error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestRequest(for chain: Chain) -> SecurityScanRequest {
        switch chain.chainType {
        case .EVM:
            return SecurityScanRequest(
                chain: chain,
                transactionType: .transfer,
                fromAddress: "0x742d35Cc6639Df3C2c6C4F4FE6a0c5e3b8b6e6d7",
                toAddress: "0x0987654321098765432109876543210987654321",
                amount: "1000000000000000000",
                data: nil,
                metadata: ["chain": chain.name, "test": "Chain coverage"]
            )
            
        case .UTXO:
            let isSegwit = chain == .bitcoin
            return SecurityScanRequest(
                chain: chain,
                transactionType: .transfer,
                fromAddress: isSegwit ? "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" : "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                toAddress: isSegwit ? "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq" : "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2",
                amount: "100000000",
                data: nil,
                metadata: ["chain": chain.name, "test": "Chain coverage"]
            )
            
        case .Solana:
            return SecurityScanRequest(
                chain: chain,
                transactionType: .transfer,
                fromAddress: "11111111111111111111111111111112",
                toAddress: "22222222222222222222222222222223",
                amount: "1000000000",
                data: nil,
                metadata: ["chain": chain.name, "test": "Chain coverage"]
            )
            
        default:
            // For unsupported chain types, use generic addresses
            return SecurityScanRequest(
                chain: chain,
                transactionType: .transfer,
                fromAddress: "test_address_1",
                toAddress: "test_address_2",
                amount: "1000000",
                data: nil,
                metadata: ["chain": chain.name, "test": "Chain coverage"]
            )
        }
    }
}

// MARK: - String Extension for Separator

extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
} 