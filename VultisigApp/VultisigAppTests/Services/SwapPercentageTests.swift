import XCTest
import BigInt
@testable import VultisigApp

class SwapPercentageTests: XCTestCase {
    
    func testBTCPercentageCalculation() {
        // Create a mock Bitcoin coin with 8 decimals
        let btcMeta = CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "btc",
            decimals: 8,
            priceProviderId: "bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
        
        let btcCoin = Coin(asset: btcMeta, address: "test", hexPublicKey: "test")
        
        // Set a small balance: 0.00021322 BTC (21322 satoshis)
        btcCoin.rawBalance = "21322"
        
        // Test 25% calculation
        let balance = btcCoin.balanceDecimal
        let twentyFivePercent = balance * 0.25
        let formattedAmount = twentyFivePercent.formatToDecimal(digits: 8)
        
        // Should be 0.00005330 BTC, not 0.0001
        XCTAssertEqual(formattedAmount, "0.00005330", "25% of 0.00021322 BTC should be 0.00005330")
        
        // Test with the actual implementation's logic (using max(4, decimals))
        let decimalsToUse = max(4, btcCoin.decimals)
        XCTAssertEqual(decimalsToUse, 8, "For BTC, should use 8 decimals")
        
        // Test all percentages
        let testCases: [(percentage: Double, expected: String)] = [
            (0.25, "0.00005330"),
            (0.50, "0.00010661"),
            (0.75, "0.00015991"),
            (1.00, "0.00021322")
        ]
        
        for testCase in testCases {
            let calculatedAmount = (balance * testCase.percentage).formatToDecimal(digits: decimalsToUse)
            XCTAssertEqual(
                calculatedAmount, 
                testCase.expected, 
                "\(Int(testCase.percentage * 100))% of 0.00021322 BTC should be \(testCase.expected)"
            )
        }
    }
    
    func testETHPercentageCalculation() {
        // Create a mock Ethereum coin with 18 decimals
        let ethMeta = CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        )
        
        let ethCoin = Coin(asset: ethMeta, address: "test", hexPublicKey: "test")
        
        // Set balance: 0.00894077 ETH
        ethCoin.rawBalance = "8940770000000000" // in wei
        
        let balance = ethCoin.balanceDecimal
        let decimalsToUse = max(4, ethCoin.decimals)
        
        // For ETH with 18 decimals, we should maintain high precision
        XCTAssertEqual(decimalsToUse, 18, "For ETH, should use 18 decimals")
        
        // Test 25% calculation
        let twentyFivePercent = (balance * 0.25).formatToDecimal(digits: decimalsToUse)
        XCTAssertEqual(twentyFivePercent, "0.00223519", "25% calculation should maintain precision")
    }
    
    func testLowDecimalCoin() {
        // Test with a coin that has less than 4 decimals (e.g., USDC with 6 decimals)
        let usdcMeta = CoinMeta(
            chain: .ethereum,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            isNativeToken: false
        )
        
        let usdcCoin = Coin(asset: usdcMeta, address: "test", hexPublicKey: "test")
        usdcCoin.rawBalance = "1000000" // 1 USDC
        
        let decimalsToUse = max(4, usdcCoin.decimals)
        XCTAssertEqual(decimalsToUse, 6, "For USDC, should use 6 decimals")
    }
} 