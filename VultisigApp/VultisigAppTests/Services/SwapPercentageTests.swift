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
        
        // For EVM chains with 18 decimals, should cap at 9
        let decimalsToUse: Int
        if ethCoin.chainType == .EVM {
            decimalsToUse = min(9, max(4, ethCoin.decimals))
        } else {
            decimalsToUse = max(4, ethCoin.decimals)
        }
        
        XCTAssertEqual(decimalsToUse, 9, "For ETH (EVM), should cap at 9 decimals")
        
        // Test 25% calculation with capped decimals
        let twentyFivePercent = (balance * 0.25).formatToDecimal(digits: decimalsToUse)
        XCTAssertEqual(twentyFivePercent, "0.002235192", "25% calculation should be capped at 9 decimals")
    }
    
    func testEVMDecimalCapping() {
        // Test various EVM tokens with different decimals
        
        // USDC - 6 decimals (should use 6)
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
        let usdcDecimalsToUse = min(9, max(4, usdcCoin.decimals))
        XCTAssertEqual(usdcDecimalsToUse, 6, "USDC should use 6 decimals")
        
        // WBTC on Ethereum - 8 decimals (should use 8)
        let wbtcMeta = CoinMeta(
            chain: .ethereum,
            ticker: "WBTC",
            logo: "wbtc",
            decimals: 8,
            priceProviderId: "wrapped-bitcoin",
            contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599",
            isNativeToken: false
        )
        
        let wbtcCoin = Coin(asset: wbtcMeta, address: "test", hexPublicKey: "test")
        let wbtcDecimalsToUse = min(9, max(4, wbtcCoin.decimals))
        XCTAssertEqual(wbtcDecimalsToUse, 8, "WBTC should use 8 decimals")
        
        // DAI - 18 decimals (should cap at 9)
        let daiMeta = CoinMeta(
            chain: .ethereum,
            ticker: "DAI",
            logo: "dai",
            decimals: 18,
            priceProviderId: "dai",
            contractAddress: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
            isNativeToken: false
        )
        
        let daiCoin = Coin(asset: daiMeta, address: "test", hexPublicKey: "test")
        let daiDecimalsToUse = min(9, max(4, daiCoin.decimals))
        XCTAssertEqual(daiDecimalsToUse, 9, "DAI should cap at 9 decimals")
    }
    
    func testNonEVMCoins() {
        // Test that non-EVM coins are not capped
        
        // Solana - 9 decimals
        let solMeta = CoinMeta(
            chain: .solana,
            ticker: "SOL",
            logo: "sol",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "",
            isNativeToken: true
        )
        
        let solCoin = Coin(asset: solMeta, address: "test", hexPublicKey: "test")
        let solDecimalsToUse = max(4, solCoin.decimals)
        XCTAssertEqual(solDecimalsToUse, 9, "SOL should use full 9 decimals without capping")
    }
} 
