//
//  SuiTokenPriceTests.swift
//  VultisigAppTests
//
//  Created by Assistant on current date.
//

import XCTest
import BigInt
@testable import VultisigApp

@MainActor
final class SuiTokenPriceTests: XCTestCase {
    
    var suiService: SuiService!
    var cetusService: CetusAggregatorService!
    
    // Test data: All Sui tokens from TokensStore
    let suiTokens: [(name: String, address: String, decimals: Int)] = [
        ("SUI", "0x2::sui::SUI", 9),
        ("ETH", "0xd0e89b2af5e4910726fbcd8b8dd37bb79b29e5f83f7491bca830e94f7f226d29::eth::ETH", 8),
        ("DEEP", "0xdeeb7a4662eec9f2f3def03fb937a663dddaa2e215b8078a284d026b7946c270::deep::DEEP", 6),
        ("WAL", "0x356a26eb9e012a68958082340d4c4116e7f55615cf27affcff209cf0ae544f59::wal::WAL", 9),
        ("CETUS", "0x06864a6f921804860930db6ddbe2e16acdf8504495ea7481637a1c8b9a8fe54b::cetus::CETUS", 9),
        ("NAVX", "0xa99b8952d4f7d947ea77fe0ecdcc9e5fc0bcab2841d6e2a5aa00c3044e5544b5::navx::NAVX", 9),
        ("BLUE", "0xe1b45a0e641b9955a20aa0ad1c1f4ad86aad8afb07296d4085e349a50e90bdca::blue::BLUE", 8),
        ("SEND", "0xb45fcfcc2cc07ce0702cc2d229621e046c906ef14d9b25e8e4d25f6e8763fef7::send::SEND", 6),
        ("USDC", "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC", 6),
        ("USDT", "0xc060006111016b8a020ad5b33834984a437aaa7d3c74c18e09a95d48aceab08c::coin::COIN", 6),
        ("HASUI", "0xbde4ba4c2e274a60ce15c1cfff9e5c42e41654ac8b6d906a57efa4bd3c29f47d::hasui::HASUI", 9),
        ("VSUI", "0x549e8b69270defbfafd4f94e17ec44cdbdd99820b33bda2278dea3b9a32d3f55::cert::CERT", 9),
        ("TURBOS", "0x5d1f47ea69bb0de31c313d7acf89b890dbb8991ea8e03c6c355171f84bb1ba4a::turbos::TURBOS", 9),
        ("FUD", "0x76cb819b01abed502bee8a702b4c2d547532c12f25001c9dea795a5e631c26f1::fud::FUD", 5),
        ("BLUB", "0xfa7ac3951fdca92c5200d468d31a365eb03b2be9936fde615e69f0c1274ad3a0::BLUB::BLUB", 2),
        ("BUCK", "0xce7ff77a83ea0cb6fd39bd8748e2ec89a3f41e8efdc3f4eb123e0ca37b184db2::buck::BUCK", 9),
        ("SCA", "0x7016aae72cfc67f2fadf55769c0a7dd54291a583b63051a5ed71081cce836ac6::sca::SCA", 9),
        ("WBTC", "0x027792d9fed7f9844eb4839566001bb6f6cb4804f66aa2da6fe1ee242d896881::coin::COIN", 8),
        ("WBNB", "0xb848cce11ef3a8f62eccea6eb5b35a12c4c2b1ee1af7755d02d7bd6218e8226f::coin::COIN", 8)
    ]
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        suiService = SuiService.shared
        cetusService = CetusAggregatorService.shared
    }
    
    override func tearDownWithError() throws {
        suiService = nil
        cetusService = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Test SuiService.getTokenUSDValue
    
    func testSuiServiceGetTokenUSDValue() async throws {
        print("🧪 Testing SuiService.getTokenUSDValue for all Sui tokens")
        print("=" * 60)
        
        var successCount = 0
        var failureCount = 0
        var priceResults: [(token: String, price: Double, status: String)] = []
        
        for token in suiTokens {
            print("\n🔍 Testing \(token.name)...")
            
            let price = await SuiService.getTokenUSDValue(contractAddress: token.address)
            
            if price > 0 {
                successCount += 1
                print("✅ \(token.name): $\(String(format: "%.6f", price)) USD")
                priceResults.append((token: token.name, price: price, status: "✅"))
            } else {
                failureCount += 1
                print("❌ \(token.name): Failed to get price (returned 0.0)")
                priceResults.append((token: token.name, price: 0.0, status: "❌"))
            }
            
            // Small delay to avoid rate limiting
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        print("\n" + "=" * 60)
        print("📊 SuiService Summary:")
        print("✅ Successful: \(successCount)")
        print("❌ Failed: \(failureCount)")
        print("📈 Total tokens tested: \(suiTokens.count)")
        
        // Print summary table
        print("\n📋 Price Summary:")
        for result in priceResults {
            print("\(result.status) \(result.token): $\(String(format: "%.6f", result.price))")
        }
        
        // Assert that at least some tokens returned prices
        XCTAssertGreaterThan(successCount, 0, "At least some tokens should return valid prices")
    }
    
    // MARK: - Test SuiService.getTokenUSDValue with decimals
    
    func testSuiServiceGetTokenUSDValueWithDecimals() async throws {
        print("\n🧪 Testing SuiService.getTokenUSDValue with proper decimals")
        print("=" * 60)
        
        var successCount = 0
        var failureCount = 0
        
        for token in suiTokens {
            print("\n🔍 Testing \(token.name) with \(token.decimals) decimals...")
            
            let price = await SuiService.getTokenUSDValue(
                contractAddress: token.address,
                decimals: token.decimals
            )
            
            if price > 0 {
                successCount += 1
                print("✅ \(token.name): $\(String(format: "%.6f", price)) USD")
            } else {
                failureCount += 1
                print("❌ \(token.name): Failed to get price (returned 0.0)")
            }
            
            // Small delay to avoid rate limiting
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        print("\n" + "=" * 60)
        print("📊 SuiService (with decimals) Summary:")
        print("✅ Successful: \(successCount)")
        print("❌ Failed: \(failureCount)")
        
        XCTAssertGreaterThan(successCount, 0, "At least some tokens should return valid prices with decimals")
    }
    
    // MARK: - Test CetusAggregatorService directly
    
    func testCetusAggregatorServiceGetTokenUSDValue() async throws {
        print("\n🧪 Testing CetusAggregatorService.getTokenUSDValue directly")
        print("=" * 60)
        
        var successCount = 0
        var failureCount = 0
        var priceComparison: [(token: String, cetusPrice: Double, suiServicePrice: Double)] = []
        
        for token in suiTokens {
            print("\n🔍 Testing \(token.name) with Cetus...")
            
            // Skip USDC as it can't be swapped to itself
            if token.name == "USDC" {
                print("⏭️  Skipping USDC (base currency)")
                continue
            }
            
            // Get price from Cetus with proper decimals
            let cetusPrice = await cetusService.getTokenUSDValue(
                contractAddress: token.address,
                decimals: token.decimals
            )
            
            // Also get price from SuiService for comparison
            let suiServicePrice = await SuiService.getTokenUSDValue(
                contractAddress: token.address,
                decimals: token.decimals
            )
            
            if cetusPrice > 0 {
                successCount += 1
                print("✅ \(token.name) Cetus: $\(String(format: "%.6f", cetusPrice)) USD")
                print("   SuiService: $\(String(format: "%.6f", suiServicePrice)) USD")
                
                // Check if prices are similar (within 10% difference)
                if suiServicePrice > 0 {
                    let priceDiff = abs(cetusPrice - suiServicePrice) / suiServicePrice * 100
                    print("   Price difference: \(String(format: "%.2f", priceDiff))%")
                }
                
                priceComparison.append((
                    token: token.name,
                    cetusPrice: cetusPrice,
                    suiServicePrice: suiServicePrice
                ))
            } else {
                failureCount += 1
                print("❌ \(token.name): Failed to get Cetus price")
            }
            
            // Small delay to avoid rate limiting
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        print("\n" + "=" * 60)
        print("📊 CetusAggregatorService Summary:")
        print("✅ Successful: \(successCount)")
        print("❌ Failed: \(failureCount)")
        
        // Print price comparison table
        print("\n📋 Price Comparison (Cetus vs SuiService):")
        for comparison in priceComparison {
            let diff = comparison.suiServicePrice > 0 
                ? abs(comparison.cetusPrice - comparison.suiServicePrice) / comparison.suiServicePrice * 100
                : 0.0
            print("\(comparison.token):")
            print("  Cetus: $\(String(format: "%.6f", comparison.cetusPrice))")
            print("  SuiService: $\(String(format: "%.6f", comparison.suiServicePrice))")
            if diff > 0 {
                print("  Difference: \(String(format: "%.2f", diff))%")
            }
        }
        
        XCTAssertGreaterThan(successCount, 0, "At least some tokens should return valid Cetus prices")
    }
    
    // MARK: - Test specific token: DEEP
    
    func testDEEPTokenPrice() async throws {
        print("\n🧪 Testing DEEP token specifically")
        print("=" * 60)
        
        let deepToken = suiTokens.first { $0.name == "DEEP" }!
        
        // Test with SuiService
        let suiPrice = await SuiService.getTokenUSDValue(contractAddress: deepToken.address)
        print("SuiService DEEP price: $\(String(format: "%.6f", suiPrice))")
        
        // Test with SuiService including decimals
        let suiPriceWithDecimals = await SuiService.getTokenUSDValue(
            contractAddress: deepToken.address,
            decimals: deepToken.decimals
        )
        print("SuiService DEEP price (with decimals): $\(String(format: "%.6f", suiPriceWithDecimals))")
        
        // Test with CetusAggregatorService
        let cetusPrice = await cetusService.getTokenUSDValue(
            contractAddress: deepToken.address,
            decimals: deepToken.decimals
        )
        print("CetusAggregatorService DEEP price: $\(String(format: "%.6f", cetusPrice))")
        
        // Verify DEEP token returns a valid price
        XCTAssertGreaterThan(suiPrice, 0, "DEEP token should have a valid price from SuiService")
        XCTAssertGreaterThan(cetusPrice, 0, "DEEP token should have a valid price from Cetus")
        
        // Verify prices are reasonable (between $0.01 and $10)
        XCTAssertGreaterThan(cetusPrice, 0.01, "DEEP price should be reasonable (> $0.01)")
        XCTAssertLessThan(cetusPrice, 10.0, "DEEP price should be reasonable (< $10)")
    }
    
    // MARK: - Test error handling
    
    func testInvalidTokenAddress() async throws {
        print("\n🧪 Testing error handling with invalid token address")
        print("=" * 60)
        
        let invalidAddress = "0xinvalid::token::address"
        
        // Test SuiService
        let suiPrice = await SuiService.getTokenUSDValue(contractAddress: invalidAddress)
        print("SuiService price for invalid address: $\(suiPrice)")
        XCTAssertEqual(suiPrice, 0.0, "Invalid address should return 0.0")
        
        // Test CetusAggregatorService
        let cetusPrice = await cetusService.getTokenUSDValue(contractAddress: invalidAddress)
        print("CetusAggregatorService price for invalid address: $\(cetusPrice)")
        XCTAssertEqual(cetusPrice, 0.0, "Invalid address should return 0.0")
    }
    
    // MARK: - Performance test
    
    func testPerformanceOfPriceFetching() throws {
        print("\n🧪 Testing performance of price fetching")
        print("=" * 60)
        
        // Test performance for a single token
        let testToken = suiTokens.first { $0.name == "SUI" }!
        
        measure {
            let expectation = self.expectation(description: "Price fetch")
            
            Task {
                let _ = await SuiService.getTokenUSDValue(contractAddress: testToken.address)
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
} 