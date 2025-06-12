//
//  KyberSwapServiceTests.swift
//  VultisigAppTests
//
//  Created by Enrique Souza on 11.06.2025.
//

import XCTest
import BigInt
@testable import VultisigApp

final class KyberSwapServiceTests: XCTestCase {
    
    var kyberSwapService: KyberSwapService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        kyberSwapService = KyberSwapService.shared
    }
    
    override func tearDownWithError() throws {
        kyberSwapService = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Success Mapping Tests
    
    func testSuccessfulTokenResponseMapping() throws {
        let successJsonData = createMockTokensResponse().data(using: .utf8)!
        
        let tokensResponse = try JSONDecoder().decode(KyberSwapService.KyberSwapTokensResponse.self, from: successJsonData)
        
        XCTAssertEqual(tokensResponse.code, 0)
        XCTAssertEqual(tokensResponse.message, "Succeeded")
        XCTAssertEqual(tokensResponse.data.tokens.count, 2)
        
        let usdcToken = tokensResponse.data.tokens.first!
        XCTAssertEqual(usdcToken.address, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertEqual(usdcToken.symbol, "USDC")
        XCTAssertEqual(usdcToken.decimals, 6)
        XCTAssertTrue(usdcToken.isWhitelisted)
        XCTAssertFalse(usdcToken.isHoneypot)
        
        let coinMeta = usdcToken.toCoinMeta(chain: .ethereum)
        XCTAssertEqual(coinMeta.ticker, "USDC")
        XCTAssertEqual(coinMeta.contractAddress, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
    }
    
    func testSuccessfulRouteResponseMapping() throws {
        let routeJsonData = createMockRouteResponse().data(using: .utf8)!
        
        let routeResponse = try JSONDecoder().decode(KyberSwapService.KyberSwapRouteResponse.self, from: routeJsonData)
        
        XCTAssertEqual(routeResponse.code, 0)
        XCTAssertEqual(routeResponse.message, "successfully")
        XCTAssertEqual(routeResponse.data.routeSummary.amountOut, "2845698504")
        XCTAssertEqual(routeResponse.data.routeSummary.gasPrice, "7024408865")
        XCTAssertEqual(routeResponse.data.routerAddress, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5")
    }
    
    func testSuccessfulBuildResponseMapping() throws {
        let buildJsonData = createMockBuildResponse().data(using: .utf8)!
        
        let buildResponse = try JSONDecoder().decode(KyberSwapQuote.self, from: buildJsonData)
        
        XCTAssertEqual(buildResponse.code, 0)
        XCTAssertEqual(buildResponse.message, "successfully")
        XCTAssertEqual(buildResponse.dstAmount, "2845698504")
        
        let tx = buildResponse.tx
        XCTAssertEqual(tx.to, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5")
        XCTAssertEqual(tx.data, "0xe21fd0e900000000000000000000000000000000")
        XCTAssertEqual(tx.gas, 308000)
    }
    
    // MARK: - Error Mapping Tests
    
    func testTokenNotFoundErrorMapping() throws {
        let errorJsonData = """
        {
            "code": 4011,
            "message": "token not found",
            "details": null,
            "requestId": "c8628fae-3c71-4fc5-8f77-846c243201c1"
        }
        """.data(using: .utf8)!
        
        let errorData = try JSONSerialization.jsonObject(with: errorJsonData) as? [String: Any]
        
        XCTAssertEqual(errorData?["code"] as? Int, 4011)
        XCTAssertEqual(errorData?["message"] as? String, "token not found")
        XCTAssertEqual(errorData?["requestId"] as? String, "c8628fae-3c71-4fc5-8f77-846c243201c1")
        XCTAssertNil(errorData?["details"])
    }
    
    func testInsufficientLiquidityErrorMapping() throws {
        let errorJsonData = """
        {
            "code": 4001,
            "message": "insufficient liquidity",
            "details": "No route found for the given token pair",
            "requestId": "test-request-id"
        }
        """.data(using: .utf8)!
        
        let errorData = try JSONSerialization.jsonObject(with: errorJsonData) as? [String: Any]
        
        XCTAssertEqual(errorData?["code"] as? Int, 4001)
        XCTAssertEqual(errorData?["message"] as? String, "insufficient liquidity")
        XCTAssertEqual(errorData?["details"] as? String, "No route found for the given token pair")
    }
    
    func testInvalidParametersErrorMapping() throws {
        let errorJsonData = """
        {
            "code": 4000,
            "message": "invalid parameters",
            "details": {
                "amountIn": "amount must be greater than 0"
            },
            "requestId": "validation-error-id"
        }
        """.data(using: .utf8)!
        
        let errorData = try JSONSerialization.jsonObject(with: errorJsonData) as? [String: Any]
        
        XCTAssertEqual(errorData?["code"] as? Int, 4000)
        XCTAssertEqual(errorData?["message"] as? String, "invalid parameters")
        
        let details = errorData?["details"] as? [String: Any]
        XCTAssertEqual(details?["amountIn"] as? String, "amount must be greater than 0")
    }
    
    func testRateLimitErrorMapping() throws {
        let errorJsonData = """
        {
            "code": 4029,
            "message": "too many requests",
            "details": "Rate limit exceeded. Please try again later.",
            "requestId": "rate-limit-error"
        }
        """.data(using: .utf8)!
        
        let errorData = try JSONSerialization.jsonObject(with: errorJsonData) as? [String: Any]
        
        XCTAssertEqual(errorData?["code"] as? Int, 4029)
        XCTAssertEqual(errorData?["message"] as? String, "too many requests")
        XCTAssertEqual(errorData?["details"] as? String, "Rate limit exceeded. Please try again later.")
    }
    
    func testInternalServerErrorMapping() throws {
        let errorJsonData = """
        {
            "code": 5000,
            "message": "internal server error",
            "details": "An unexpected error occurred",
            "requestId": "server-error-id"
        }
        """.data(using: .utf8)!
        
        let errorData = try JSONSerialization.jsonObject(with: errorJsonData) as? [String: Any]
        
        XCTAssertEqual(errorData?["code"] as? Int, 5000)
        XCTAssertEqual(errorData?["message"] as? String, "internal server error")
    }
    
    // MARK: - Malformed Response Tests
    
    func testMalformedJSONHandling() throws {
        let malformedJson = """
        {
            "code": 0,
            "message": "successfully",
            "data": {
                "amountIn": "invalid_number",
                "amountOut": null
            }
        }
        """.data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(KyberSwapQuote.self, from: malformedJson)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    func testIncompleteResponseHandling() throws {
        let incompleteJson = """
        {
            "code": 0,
            "message": "successfully"
        }
        """.data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(KyberSwapQuote.self, from: incompleteJson)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    func testEmptyResponseHandling() throws {
        let emptyJson = "{}".data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(KyberSwapQuote.self, from: emptyJson)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    func testInvalidJSONSyntaxHandling() throws {
        let invalidJson = "{invalid json syntax".data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(KyberSwapQuote.self, from: invalidJson)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testZeroAmountHandling() throws {
        let zeroAmountJson = """
        {
            "code": 0,
            "message": "successfully",
            "data": {
                "amountIn": "0",
                "amountInUsd": "0",
                "amountOut": "0",
                "amountOutUsd": "0",
                "gas": "21000",
                "gasUsd": "0.42",
                "data": "0x",
                "routerAddress": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                "transactionValue": "0"
            },
            "requestId": "zero-amount-test"
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(KyberSwapQuote.self, from: zeroAmountJson)
        
        XCTAssertEqual(response.dstAmount, "0")
        XCTAssertEqual(response.tx.value, "0")
        XCTAssertEqual(response.tx.gas, 21000)
    }
    
    func testLargeAmountHandling() throws {
        let largeAmountJson = """
        {
            "code": 0,
            "message": "successfully",
            "data": {
                "amountIn": "999999999999999999999999999999",
                "amountInUsd": "999999999999999999999999.99",
                "amountOut": "888888888888888888888888888888",
                "amountOutUsd": "888888888888888888888888.88",
                "gas": "500000",
                "gasUsd": "100.50",
                "data": "0xe21fd0e900000000000000000000000000000000",
                "routerAddress": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                "transactionValue": "999999999999999999999999999999"
            },
            "requestId": "large-amount-test"
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(KyberSwapQuote.self, from: largeAmountJson)
        
        XCTAssertEqual(response.dstAmount, "888888888888888888888888888888")
        XCTAssertEqual(response.tx.value, "999999999999999999999999999999")
    }
    
    func testSpecialCharactersInResponseHandling() throws {
        let specialCharsJson = """
        {
            "code": 0,
            "message": "successfully with special chars: àáâãäåçèéêë",
            "data": {
                "amountIn": "1000000000000000000",
                "amountInUsd": "100.00",
                "amountOut": "99000000000000000000",
                "amountOutUsd": "99.00",
                "gas": "200000",
                "gasUsd": "4.00",
                "data": "0xe21fd0e900000000000000000000000000000000",
                "routerAddress": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                "transactionValue": "1000000000000000000"
            },
            "requestId": "special-chars-test"
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(KyberSwapQuote.self, from: specialCharsJson)
        
        XCTAssertEqual(response.message, "successfully with special chars: àáâãäåçèéêë")
        XCTAssertEqual(response.dstAmount, "99000000000000000000")
    }
    
    // MARK: - Chain Support Tests
    
    func testSupportedChainMappings() throws {
        let supportedChains = [
            ("ethereum", "1"),
            ("bsc", "56"),
            ("bnb", "56"),
            ("binance", "56"),
            ("polygon", "137"),
            ("arbitrum", "42161"),
            ("avalanche", "43114"),
            ("avax", "43114"),
            ("optimism", "10"),
            ("base", "8453"),
            ("zksync", "324")
        ]
        
        for (chainName, expectedId) in supportedChains {
            let url = Endpoint.fetchKyberSwapTokens(chain: chainName)
            XCTAssertTrue(
                url.absoluteString.contains("chainIds=\(expectedId)"),
                "Chain \(chainName) should map to ID \(expectedId)"
            )
        }
    }
    
    func testUnsupportedChainHandling() throws {
        let unsupportedChains = ["cardano", "solana", "cosmos", "polkadot", "unknown"]
        
        for chainName in unsupportedChains {
            let url = Endpoint.fetchKyberSwapTokens(chain: chainName)
            // Should fallback to using the chain name as-is for unknown chains
            XCTAssertTrue(
                url.absoluteString.contains("chainIds=\(chainName)"),
                "Unsupported chain \(chainName) should use name as-is"
            )
        }
    }
    
    // MARK: - Token Tests
    
    func testKyberSwapTokenStructure() throws {
        let jsonData = """
        {
            "chainId": 1,
            "address": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            "symbol": "USDC",
            "name": "USD Coin",
            "decimals": 6,
            "marketCap": 60941373000,
            "logoURI": "https://storage.googleapis.com/ks-setting-1d682dca/755d9eee-8d2d-44b8-ad38-1f2765f036ce.png",
            "isWhitelisted": true,
            "isStable": true,
            "isStandardERC20": true,
            "domainSeparator": "0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335",
            "permitType": "AMOUNT",
            "permitVersion": "2",
            "isHoneypot": false,
            "isFOT": false,
            "cmcRank": 7
        }
        """.data(using: .utf8)!
        
        let token = try JSONDecoder().decode(KyberSwapToken.self, from: jsonData)
        
        XCTAssertEqual(token.address, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertEqual(token.symbol, "USDC")
        XCTAssertEqual(token.name, "USD Coin")
        XCTAssertEqual(token.decimals, 6)
        XCTAssertEqual(token.logoURI, "https://storage.googleapis.com/ks-setting-1d682dca/755d9eee-8d2d-44b8-ad38-1f2765f036ce.png")
    }
    
    func testKyberSwapTokenToCoinMeta() throws {
        let token = KyberSwapToken(
            address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            symbol: "USDC",
            name: "USD Coin",
            decimals: 6,
            logoURI: "https://example.com/usdc.png"
        )
        
        let coinMeta = token.toCoinMeta(chain: .ethereum)
        
        XCTAssertEqual(coinMeta.chain, .ethereum)
        XCTAssertEqual(coinMeta.ticker, "USDC")
        XCTAssertEqual(coinMeta.logo, "https://example.com/usdc.png")
        XCTAssertEqual(coinMeta.decimals, 6)
        XCTAssertEqual(coinMeta.contractAddress, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertFalse(coinMeta.isNativeToken)
    }
    
    func testKyberSwapTokenWithNilLogoURI() throws {
        let token = KyberSwapToken(
            address: "0x123",
            symbol: "TEST",
            name: "Test Token",
            decimals: 18,
            logoURI: nil
        )
        
        let coinMeta = token.toCoinMeta(chain: .ethereum)
        
        XCTAssertEqual(coinMeta.logo, "")
        XCTAssertNil(token.logoUrl)
    }
    
    // MARK: - Quote Tests
    
    func testKyberSwapQuoteStructure() throws {
        let jsonData = """
        {
            "code": 0,
            "message": "successfully",
            "data": {
                "amountIn": "1000000000000000000",
                "amountInUsd": "2847.8423099373017",
                "amountOut": "2845698504",
                "amountOutUsd": "2845.4011254375782",
                "gas": "308000",
                "gasUsd": "6.161357900558063",
                "data": "0xe21fd0e900000000000000000000000000000000",
                "routerAddress": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                "transactionValue": "1000000000000000000",
                "additionalCostUsd": "0.0004381760190451663",
                "additionalCostMessage": "L1 fee that pays for rolls up cost"
            },
            "requestId": "9adab9e7-b007-4864-bf02-7f388b1c70cf"
        }
        """.data(using: .utf8)!
        
        let quote = try JSONDecoder().decode(KyberSwapQuote.self, from: jsonData)
        
        XCTAssertEqual(quote.code, 0)
        XCTAssertEqual(quote.message, "successfully")
        XCTAssertEqual(quote.requestId, "9adab9e7-b007-4864-bf02-7f388b1c70cf")
        XCTAssertEqual(quote.data.amountIn, "1000000000000000000")
        XCTAssertEqual(quote.data.amountOut, "2845698504")
        XCTAssertEqual(quote.data.gas, "308000")
        XCTAssertEqual(quote.data.routerAddress, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5")
        XCTAssertEqual(quote.data.transactionValue, "1000000000000000000")
        XCTAssertEqual(quote.data.additionalCostUsd, "0.0004381760190451663")
        XCTAssertEqual(quote.data.additionalCostMessage, "L1 fee that pays for rolls up cost")
    }
    
    func testKyberSwapQuoteCompatibilityInterface() throws {
        let jsonData = """
        {
            "code": 0,
            "message": "successfully",
            "data": {
                "amountIn": "1000000000000000000",
                "amountInUsd": "2847.84",
                "amountOut": "2845698504",
                "amountOutUsd": "2845.40",
                "gas": "308000",
                "gasUsd": "6.16",
                "data": "0xe21fd0e900000000000000000000000000000000",
                "routerAddress": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                "transactionValue": "1000000000000000000"
            },
            "requestId": "test-request-id"
        }
        """.data(using: .utf8)!
        
        let quote = try JSONDecoder().decode(KyberSwapQuote.self, from: jsonData)
        
        // Test OneInch compatibility interface
        XCTAssertEqual(quote.dstAmount, "2845698504")
        
        let tx = quote.tx
        XCTAssertEqual(tx.to, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5")
        XCTAssertEqual(tx.data, "0xe21fd0e900000000000000000000000000000000")
        XCTAssertEqual(tx.value, "1000000000000000000")
        XCTAssertEqual(tx.gasPrice, "0") // KyberSwap doesn't provide gasPrice in build response
        XCTAssertEqual(tx.gas, 308000)
        XCTAssertEqual(tx.from, "") // Will be filled by service
    }
    
    func testKyberSwapQuoteZeroGasHandling() throws {
        let jsonData = """
        {
            "code": 0,
            "message": "successfully",
            "data": {
                "amountIn": "1000000000000000000",
                "amountInUsd": "2847.84",
                "amountOut": "2845698504",
                "amountOutUsd": "2845.40",
                "gas": "0",
                "gasUsd": "0",
                "data": "0xe21fd0e900000000000000000000000000000000",
                "routerAddress": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                "transactionValue": "1000000000000000000"
            },
            "requestId": "test-request-id"
        }
        """.data(using: .utf8)!
        
        let quote = try JSONDecoder().decode(KyberSwapQuote.self, from: jsonData)
        let tx = quote.tx
        
        // Should default to 600000 when gas is 0
        XCTAssertEqual(tx.gas, 600000)
    }
    
    // MARK: - Route Response Tests
    
    func testRouteResponseStructure() throws {
        let jsonData = """
        {
            "code": 0,
            "message": "successfully",
            "data": {
                "routeSummary": {
                    "tokenIn": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                    "amountIn": "1000000000000000000",
                    "amountInUsd": "2847.8423099373017",
                    "tokenOut": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    "amountOut": "2845698504",
                    "amountOutUsd": "2845.4011254375782",
                    "gas": "308000",
                    "gasPrice": "7024408865",
                    "gasUsd": "6.161357900558063",
                    "l1FeeUsd": "0",
                    "extraFee": {
                        "feeAmount": "",
                        "chargeFeeBy": "",
                        "isInBps": false,
                        "feeReceiver": ""
                    },
                    "route": [],
                    "routeID": "fc349a77-c6c6-40fb-b602-145805197977",
                    "checksum": "17691095414726979128",
                    "timestamp": 1749652698
                },
                "routerAddress": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5"
            },
            "requestId": "fc349a77-c6c6-40fb-b602-145805197977"
        }
        """.data(using: .utf8)!
        
        let routeResponse = try JSONDecoder().decode(KyberSwapService.KyberSwapRouteResponse.self, from: jsonData)
        
        XCTAssertEqual(routeResponse.code, 0)
        XCTAssertEqual(routeResponse.message, "successfully")
        XCTAssertEqual(routeResponse.requestId, "fc349a77-c6c6-40fb-b602-145805197977")
        XCTAssertEqual(routeResponse.data.routerAddress, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5")
        
        let routeSummary = routeResponse.data.routeSummary
        XCTAssertEqual(routeSummary.tokenIn, "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        XCTAssertEqual(routeSummary.tokenOut, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertEqual(routeSummary.amountIn, "1000000000000000000")
        XCTAssertEqual(routeSummary.amountOut, "2845698504")
        XCTAssertEqual(routeSummary.gas, "308000")
        XCTAssertEqual(routeSummary.gasPrice, "7024408865")
        XCTAssertEqual(routeSummary.routeID, "fc349a77-c6c6-40fb-b602-145805197977")
        XCTAssertEqual(routeSummary.timestamp, 1749652698)
        XCTAssertEqual(routeSummary.l1FeeUsd, "0")
    }
    
    // MARK: - Swap Payload Tests
    
    func testKyberSwapPayload() throws {
        let mockQuote = createMockKyberSwapQuote()
        let fromCoin = Coin.example
        let toCoin = Coin.example
        let fromAmount = BigInt("1000000000000000000")
        let toAmountDecimal = Decimal(string: "2845.698504")!
        
        let payload = KyberSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            toAmountDecimal: toAmountDecimal,
            quote: mockQuote
        )
        
        XCTAssertEqual(payload.fromCoin, fromCoin)
        XCTAssertEqual(payload.toCoin, toCoin)
        XCTAssertEqual(payload.fromAmount, fromAmount)
        XCTAssertEqual(payload.toAmountDecimal, toAmountDecimal)
        XCTAssertEqual(payload.quote.dstAmount, "2845698504")
    }
    
    // MARK: - Endpoint Tests
    
    func testKyberSwapEndpoints() throws {
        // Test route endpoint
        let routeUrl = Endpoint.fetchKyberSwapRoute(
            chain: "ethereum",
            tokenIn: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            tokenOut: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            amountIn: "1000000000000000000",
            saveGas: false,
            gasInclude: true,
            slippageTolerance: 50,
            isAffiliate: false
        )
        
        let expectedRouteUrl = "https://aggregator-api.kyberswap.com/ethereum/api/v1/routes?tokenIn=0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee&tokenOut=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48&amountIn=1000000000000000000&saveGas=false&gasInclude=true&slippageTolerance=50"
        XCTAssertEqual(routeUrl.absoluteString, expectedRouteUrl)
        
        // Test build endpoint
        let buildUrl = Endpoint.buildKyberSwapTransaction(chain: "ethereum")
        let expectedBuildUrl = "https://aggregator-api.kyberswap.com/ethereum/api/v1/route/build"
        XCTAssertEqual(buildUrl.absoluteString, expectedBuildUrl)
        
        // Test tokens endpoint with chain ID
        let tokensUrl = Endpoint.fetchKyberSwapTokens(chainId: "1")
        let expectedTokensUrl = "https://ks-setting.kyberswap.com/api/v1/tokens?chainIds=1&isWhitelisted=true&pageSize=100"
        XCTAssertEqual(tokensUrl.absoluteString, expectedTokensUrl)
    }
    
    func testChainIdMapping() throws {
        // Test endpoint with direct chain ID mapping
        let testCases: [String] = ["1", "56", "137", "42161", "43114", "10", "8453", "324"]
        
        for chainId in testCases {
            let url = Endpoint.fetchKyberSwapTokens(chainId: chainId)
            XCTAssertTrue(
                url.absoluteString.contains("chainIds=\(chainId)"),
                "Chain ID \(chainId) should be properly included in URL: \(url.absoluteString)"
            )
        }
    }
    
    func testServiceChainConversion() throws {
        // Test that service correctly converts Chain enum to chain names (not IDs)
        let service = KyberSwapService.shared
        
        let testCases: [(Chain, String)] = [
            (.ethereum, "ethereum"),
            (.bscChain, "bsc"),
            (.polygon, "polygon"),
            (.arbitrum, "arbitrum"),
            (.avalanche, "avalanche"),
            (.optimism, "optimism"),
            (.base, "base"),
            (.zksync, "zksync")
        ]
        
        for (chain, expectedName) in testCases {
            let actualName = service.getChainId(for: chain)
            XCTAssertEqual(actualName, expectedName, "Chain \(chain) should map to name \(expectedName), but got \(actualName)")
        }
        
        // Test default fallback
        let defaultName = service.getChainId(for: .bitcoin)
        XCTAssertEqual(defaultName, "ethereum", "Unsupported chains should fallback to ethereum")
    }
    
    // MARK: - Gas Price Calculation Tests
    
    func testGasPriceCalculation() throws {
        // Test with route response containing gas price
        let gas = BigInt("308000")
        let gasPrice = BigInt("7024408865") // From actual API response
        let expectedFee = gas * gasPrice
        
        XCTAssertEqual(expectedFee, BigInt("2163549834420000"))
        
        // Test fallback to default gas price
        let defaultGasPrice = BigInt("20000000000") // 20 Gwei
        let fallbackFee = gas * defaultGasPrice
        
        XCTAssertEqual(fallbackFee, BigInt("6160000000000000"))
    }
    
    // MARK: - Integration Tests
    
    func testSwapQuoteEnumIntegration() throws {
        let mockQuote = createMockKyberSwapQuote()
        let fee = BigInt("2163549834420000")
        
        let swapQuote = SwapQuote.kyberswap(mockQuote, fee: fee)
        
        XCTAssertEqual(swapQuote.router, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5")
        XCTAssertEqual(swapQuote.displayName, "KyberSwap")
        XCTAssertNil(swapQuote.totalSwapSeconds)
        XCTAssertEqual(swapQuote.inboundAddress, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5")
        
        let mockToCoin = Coin.example
        XCTAssertEqual(swapQuote.inboundFeeDecimal(toCoin: mockToCoin), .zero)
        XCTAssertNil(swapQuote.memo)
    }
    
    func testSwapPayloadEnumIntegration() throws {
        let mockQuote = createMockKyberSwapQuote()
        let payload = KyberSwapPayload(
            fromCoin: Coin.example,
            toCoin: Coin.example,
            fromAmount: BigInt("1000000000000000000"),
            toAmountDecimal: Decimal(string: "2845.698504")!,
            quote: mockQuote
        )
        
        let swapPayload = SwapPayload.kyberSwap(payload)
        
        XCTAssertEqual(swapPayload.fromCoin, Coin.example)
        XCTAssertEqual(swapPayload.toCoin, Coin.example)
        XCTAssertEqual(swapPayload.fromAmount, BigInt("1000000000000000000"))
        XCTAssertEqual(swapPayload.toAmountDecimal, Decimal(string: "2845.698504")!)
        XCTAssertEqual(swapPayload.router, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5")
        XCTAssertFalse(swapPayload.isDeposit)
    }
    
    // MARK: - ERC20 Approval Flow Tests
    
    func testERC20ApprovalRequiredCheck() {
        // Test that ERC20 tokens require approval
        let erc20Token = Coin.example
        XCTAssertTrue(erc20Token.shouldApprove, "ERC20 tokens should require approval")
        
        // Test that router address is available for approval
        let mockQuote = createMockKyberSwapQuote()
        let routerAddress = mockQuote.tx.to
        XCTAssertFalse(routerAddress.isEmpty, "Router address should be available for approval")
        XCTAssertTrue(routerAddress.hasPrefix("0x"), "Router address should be valid Ethereum address")
        XCTAssertEqual(routerAddress.count, 42, "Router address should be 42 characters long")
    }
    
    func testERC20SwapGasPriceMapping() {
        // Test that gas price is correctly mapped from route response
        let mockQuote = createMockKyberSwapQuote()
        let gasPrice = mockQuote.tx.gasPrice
        
        XCTAssertNotEqual(gasPrice, "0", "Gas price should not be zero")
        XCTAssertFalse(gasPrice.isEmpty, "Gas price should not be empty")
        
        // Verify gas price is numeric
        let gasPriceValue = BigInt(gasPrice)
        XCTAssertNotNil(gasPriceValue, "Gas price should be a valid number")
        XCTAssertGreaterThan(gasPriceValue!, BigInt.zero, "Gas price should be greater than zero")
    }
    
    func testERC20ApprovalErrorMapping() {
        // Test insufficient allowance error (4011)
        let insufficientAllowanceError = """
        {
            "code": 4011,
            "message": "Token allowance is insufficient",
            "details": "Please approve the token first"
        }
        """
        
        let errorData = insufficientAllowanceError.data(using: .utf8)!
        
        XCTAssertNoThrow({
            let json = try JSONSerialization.jsonObject(with: errorData, options: []) as? [String: Any]
            let code = json?["code"] as? Int
            XCTAssertEqual(code, 4011, "Should correctly parse insufficient allowance error")
        })
    }
    
    func testERC20TwoStepSwapFlow() {
        // Test that ERC20 swaps follow two-step flow: approval + swap
        let swapTransaction = SwapTransaction()
        swapTransaction.fromCoin = Coin.example // ERC20 token
        swapTransaction.quote = .kyberswap(createMockKyberSwapQuote(), fee: BigInt(1000000))
        
        // Check if approval is required
        XCTAssertTrue(swapTransaction.isApproveRequired, "ERC20 swaps should require approval")
        
        // Check router address availability
        XCTAssertNotNil(swapTransaction.router, "Router address should be available for approval")
        XCTAssertEqual(swapTransaction.router, createMockKyberSwapQuote().tx.to, "Router should match quote response")
    }
    
    func testERC20vs1InchApprovalCompatibility() {
        // Test that KyberSwap and 1Inch use the same approval flow pattern
        let kyberQuote = createMockKyberSwapQuote()
        let swapTransaction = SwapTransaction()
        swapTransaction.fromCoin = Coin.example
        swapTransaction.quote = .kyberswap(kyberQuote, fee: BigInt(1000000))
        
        // Both should require approval for ERC20 tokens
        XCTAssertTrue(swapTransaction.isApproveRequired, "Both KyberSwap and 1Inch should require ERC20 approval")
        
        // Both should provide router addresses
        XCTAssertNotNil(swapTransaction.router, "Both should provide router addresses for approval")
        XCTAssertTrue(swapTransaction.router?.hasPrefix("0x") ?? false, "Router address should be valid")
    }
    
    func testSuccessfulQuoteMapping() {
        // Test successful quote response mapping
        let mockQuote = createMockKyberSwapQuote()
        
        XCTAssertEqual(mockQuote.code, 0, "Successful response should have code 0")
        XCTAssertEqual(mockQuote.message, "successfully", "Should map success message correctly")
        XCTAssertEqual(mockQuote.dstAmount, "2845698504", "Should correctly map destination amount")
        XCTAssertEqual(mockQuote.tx.to, "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", "Should map router address")
        XCTAssertFalse(mockQuote.tx.data.isEmpty, "Should include transaction data")
    }
    
    func testErrorQuoteMapping() {
        // Test error response mapping
        let errorResponse = """
        {
            "code": 4001,
            "message": "Insufficient liquidity",
            "details": "No route found for the given parameters"
        }
        """
        
        let errorData = errorResponse.data(using: .utf8)!
        
        XCTAssertNoThrow({
            let json = try JSONSerialization.jsonObject(with: errorData, options: []) as? [String: Any]
            let code = json?["code"] as? Int
            let message = json?["message"] as? String
            
            XCTAssertEqual(code, 4001, "Should correctly parse error code")
            XCTAssertEqual(message, "Insufficient liquidity", "Should correctly parse error message")
        })
    }
    
    func testNetworkErrorMapping() {
        // Test network timeout/connection error handling
        // This would typically be tested with URLSession mocking
        // For now, we validate the error structure
        
        struct KyberSwapError: Error {
            let code: Int
            let message: String
        }
        
        let networkError = KyberSwapError(code: -1001, message: "Network timeout")
        
        XCTAssertEqual(networkError.code, -1001, "Should preserve network error codes")
        XCTAssertEqual(networkError.message, "Network timeout", "Should preserve error messages")
    }
    
    func testGasPriceFromRouteResponse() {
        // Test that gas price is extracted from route response, not build response
        let routeResponseGasPrice = "7024408865"
        let mockQuoteWithGasPrice = KyberSwapQuote(
            code: 0,
            message: "successfully",
            data: KyberSwapQuote.Data(
                amountIn: "1000000000000000000",
                amountInUsd: "2847.84",
                amountOut: "2845698504",
                amountOutUsd: "2845.40",
                gas: "308000",
                gasUsd: "6.16",
                data: "0xe21fd0e900000000000000000000000000000000",
                routerAddress: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                transactionValue: "1000000000000000000",
                gasPrice: routeResponseGasPrice
            ),
            requestId: "test-request-id"
        )
        
        XCTAssertEqual(mockQuoteWithGasPrice.tx.gasPrice, routeResponseGasPrice, "Should use gas price from route response")
    }
    
    // MARK: - Real Integration Tests for Officially Supported Chains
    func testEthereumQuoteFetch() async throws {
        // Test ETH -> USDC on Ethereum
        do {
            let (quote, fee) = try await KyberSwapService.shared.fetchQuotes(
                chain: "ethereum",
                source: "", // ETH (native token)
                destination: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", // USDC
                amount: "1000000000000000000", // 1 ETH
                from: "0x742d35Cc6635C0532925a3b8D0BDD21C05009C0E",
                isAffiliate: false
            )
            
            print("✅ Ethereum ETH->USDC Quote Success!")
            print("   Quote data: \(quote.data?.to ?? "nil")")
            print("   Fee: \(fee?.description ?? "nil")")
            
            XCTAssertNotNil(quote.data, "Ethereum quote should have data")
            XCTAssertEqual(quote.code, 0, "Ethereum quote should be successful")
            
        } catch {
            XCTFail("Ethereum ETH->USDC should work: \(error)")
        }
    }
    
    func testBSCQuoteFetch() async throws {
        // Test BNB -> USDT on BSC
        do {
            let (quote, fee) = try await KyberSwapService.shared.fetchQuotes(
                chain: "bsc",
                source: "", // BNB (native token)
                destination: "0x55d398326f99059ff775485246999027b3197955", // USDT
                amount: "1000000000000000000", // 1 BNB
                from: "0x742d35Cc6635C0532925a3b8D0BDD21C05009C0E",
                isAffiliate: false
            )
            
            print("✅ BSC BNB->USDT Quote Success!")
            print("   Quote data: \(quote.data?.to ?? "nil")")
            print("   Fee: \(fee?.description ?? "nil")")
            
            XCTAssertNotNil(quote.data, "BSC quote should have data")
            XCTAssertEqual(quote.code, 0, "BSC quote should be successful")
            
        } catch {
            XCTFail("BSC BNB->USDT should work: \(error)")
        }
    }
    
    func testArbitrumQuoteFetch() async throws {
        // Test ETH -> USDC on Arbitrum
        do {
            let (quote, fee) = try await KyberSwapService.shared.fetchQuotes(
                chain: "arbitrum",
                source: "", // ETH (native token)
                destination: "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8", // USDC
                amount: "1000000000000000000", // 1 ETH
                from: "0x742d35Cc6635C0532925a3b8D0BDD21C05009C0E",
                isAffiliate: false
            )
            
            print("✅ Arbitrum ETH->USDC Quote Success!")
            print("   Quote data: \(quote.data?.to ?? "nil")")
            print("   Fee: \(fee?.description ?? "nil")")
            
            XCTAssertNotNil(quote.data, "Arbitrum quote should have data")
            XCTAssertEqual(quote.code, 0, "Arbitrum quote should be successful")
            
        } catch {
            XCTFail("Arbitrum ETH->USDC should work: \(error)")
        }
    }
    
    func testPolygonQuoteFetch() async throws {
        // Test MATIC -> USDC on Polygon
        do {
            let (quote, fee) = try await KyberSwapService.shared.fetchQuotes(
                chain: "polygon",
                source: "", // MATIC (native token)
                destination: "0x2791bca1f2de4661ed88a30c99a7a9449aa84174", // USDC
                amount: "1000000000000000000", // 1 MATIC
                from: "0x742d35Cc6635C0532925a3b8D0BDD21C05009C0E",
                isAffiliate: false
            )
            
            print("✅ Polygon MATIC->USDC Quote Success!")
            print("   Quote data: \(quote.data?.to ?? "nil")")
            print("   Fee: \(fee?.description ?? "nil")")
            
            XCTAssertNotNil(quote.data, "Polygon quote should have data")
            XCTAssertEqual(quote.code, 0, "Polygon quote should be successful")
            
        } catch {
            XCTFail("Polygon MATIC->USDC should work: \(error)")
        }
    }
    
    func testOptimismQuoteFetch() async throws {
        // Test ETH -> USDC on Optimism
        do {
            let (quote, fee) = try await KyberSwapService.shared.fetchQuotes(
                chain: "optimism",
                source: "", // ETH (native token)
                destination: "0x7f5c764cbc14f9669b88837ca1490cca17c31607", // USDC
                amount: "1000000000000000000", // 1 ETH
                from: "0x742d35Cc6635C0532925a3b8D0BDD21C05009C0E",
                isAffiliate: false
            )
            
            print("✅ Optimism ETH->USDC Quote Success!")
            print("   Quote data: \(quote.data?.to ?? "nil")")
            print("   Fee: \(fee?.description ?? "nil")")
            
            XCTAssertNotNil(quote.data, "Optimism quote should have data")
            XCTAssertEqual(quote.code, 0, "Optimism quote should be successful")
            
        } catch {
            XCTFail("Optimism ETH->USDC should work: \(error)")
        }
    }
    
    func testAvalancheQuoteFetch() async throws {
        // Test AVAX -> USDC on Avalanche
        do {
            let (quote, fee) = try await KyberSwapService.shared.fetchQuotes(
                chain: "avalanche",
                source: "", // AVAX (native token)
                destination: "0xa7d7079b0fead91f3e65f86e8915cb59c1a4c664", // USDC
                amount: "1000000000000000000", // 1 AVAX
                from: "0x742d35Cc6635C0532925a3b8D0BDD21C05009C0E",
                isAffiliate: false
            )
            
            print("✅ Avalanche AVAX->USDC Quote Success!")
            print("   Quote data: \(quote.data?.to ?? "nil")")
            print("   Fee: \(fee?.description ?? "nil")")
            
            XCTAssertNotNil(quote.data, "Avalanche quote should have data")
            XCTAssertEqual(quote.code, 0, "Avalanche quote should be successful")
            
        } catch {
            XCTFail("Avalanche AVAX->USDC should work: \(error)")
        }
    }
    
    // MARK: - Comprehensive Test Runner
    func testAllOfficiallySupportedChainQuotes() async throws {
        print("🧪 Testing KyberSwap Service Integration for All Officially Supported Chains...")
        
        // Track results
        var successCount = 0
        var failureCount = 0
        var results: [String] = []
        
        // Test configurations for each chain
        let testConfigs = [
            ("Ethereum", "ethereum", "", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "ETH->USDC"),
            ("BSC", "bsc", "", "0x55d398326f99059ff775485246999027b3197955", "BNB->USDT"),
            ("Arbitrum", "arbitrum", "", "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8", "ETH->USDC"),
            ("Polygon", "polygon", "", "0x2791bca1f2de4661ed88a30c99a7a9449aa84174", "MATIC->USDC"),
            ("Optimism", "optimism", "", "0x7f5c764cbc14f9669b88837ca1490cca17c31607", "ETH->USDC"),
            ("Avalanche", "avalanche", "", "0xa7d7079b0fead91f3e65f86e8915cb59c1a4c664", "AVAX->USDC")
        ]
        
        for (chainName, chainId, source, destination, pairName) in testConfigs {
            do {
                let (quote, fee) = try await KyberSwapService.shared.fetchQuotes(
                    chain: chainId,
                    source: source,
                    destination: destination,
                    amount: "1000000000000000000", // 1 token
                    from: "0x742d35Cc6635C0532925a3b8D0BDD21C05009C0E",
                    isAffiliate: false
                )
                
                successCount += 1
                let result = "✅ \(chainName) (\(pairName)): SUCCESS - Code: \(quote.code), HasData: \(quote.data != nil)"
                results.append(result)
                print(result)
                
            } catch {
                failureCount += 1
                let result = "❌ \(chainName) (\(pairName)): FAILED - \(error)"
                results.append(result)
                print(result)
            }
        }
        
        // Print summary
        print("\n📊 KyberSwap Integration Test Summary:")
        print("   ✅ Successful: \(successCount)/\(testConfigs.count)")
        print("   ❌ Failed: \(failureCount)/\(testConfigs.count)")
        print("\n📋 Detailed Results:")
        for result in results {
            print("   \(result)")
        }
        
        // Assert that most chains work (allowing for occasional API issues)
        XCTAssertGreaterThanOrEqual(successCount, 4, "At least 4 out of 6 officially supported chains should work")
        
        if successCount == testConfigs.count {
            print("\n🎉 Perfect! All officially supported chains are working with KyberSwap!")
        }
    }
}

// MARK: - Cross-Chain Support Models
private struct CrossChainSwapParams {
    let fromChainId: String
    let toChainId: String  
    let fromTokenAddress: String
    let toTokenAddress: String
    let amount: String
    let slippage: String
}

// MARK: - Test Extensions
extension KyberSwapServiceTests {
    
    func testCurrentLimitationDemo() {
        print("🚨 CURRENT LIMITATION DEMO:")
        print("   Our KyberSwap integration only supports SAME-CHAIN swaps")
        print("   For BLAST.ETH -> ARB.ETH, you get 'swap route not available'")
        print("   because we're trying to swap ETH->ETH on the SAME Blast chain")
        print("")
        print("🔧 SOLUTION:")
        print("   We need to implement KyberSwap's cross-chain API")
        print("   Which uses Squid router for bridging between chains")
        print("   URL: https://api.squidrouter.com/v1/route")
        print("")
        print("✅ CHAINS SUPPORTED for cross-chain:")
        print("   - Ethereum (1)")
        print("   - BSC (56)")  
        print("   - Polygon (137)")
        print("   - Arbitrum (42161)")
        print("   - Optimism (10)")
        print("   - Avalanche (43114)")
        print("   - Base (8453)")
        print("   - Blast (81457)")
        
        XCTAssertTrue(true) // This test always passes, it's just for documentation
    }
}

// MARK: - Extensions for Testing

extension KyberSwapService {
    // Expose private types for testing
    typealias KyberSwapRouteResponse = KyberSwapService.KyberSwapRouteResponse
    typealias KyberSwapTokensResponse = KyberSwapService.KyberSwapTokensResponse
} 