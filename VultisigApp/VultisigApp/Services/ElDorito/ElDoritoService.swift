//
//  ElDoritoService.swift
//  VoltixApp
//
//  Created by Enrique Souza
//

import Foundation
import BigInt

struct ElDoritoService {
    
    static let shared = ElDoritoService()
    
    private var nullAddress: String {
        return "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }
    
    private var referrerAddress: String {
        return "0xa4a4f610e89488eb4ecc6c63069f241a54485269"
    }
    
    func getTokenIdentifier(fromCoin: Coin, toCoin: Coin) async throws -> (String, String) {
        let tokens = try await fetchTokens()
                
        let fromToken = tokens.first { $0.ticker.uppercased() == fromCoin.ticker.uppercased() && $0.chain.uppercased() == fromCoin.chain.swapAsset.uppercased() }
        
        guard let fromCoinIdentifier = fromToken?.identifier else {
            throw NSError(domain: "El Dorito Service", code: 1001, userInfo: [NSLocalizedDescriptionKey : "From Token Identifier not found"])
        }
        
        let toToken = tokens.first { $0.ticker.uppercased() == toCoin.ticker.uppercased() && $0.chain.uppercased() == toCoin.chain.swapAsset.uppercased() }
        
        guard let toCoinIdentifier = toToken?.identifier else {
            throw NSError(domain: "El Dorito Service", code: 1001, userInfo: [NSLocalizedDescriptionKey : "To Token Identifier not found"])
        }
        
        return (fromCoinIdentifier, toCoinIdentifier)
    }
    
    func fetchTokens() async throws -> [ElDoritoToken] {
        let url = Endpoint.fetchElDoritoTokens(provider: "THORCHAIN")
        
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10 // Optional timeout
        
        // Fetch data with caching enabled
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            let headers = httpResponse.allHeaderFields
            
            if let cacheControl = headers["Cache-Control"] as? String, cacheControl.contains("max-age") {
                print("Server provides Cache-Control: \(cacheControl)")
                // URLSession will automatically handle caching as specified by the server
            } else {
                print("No Cache-Control found, manually caching for 1 hour.")
                
                // Create a new response with 1-hour cache control header
                var newHeaderFields = [String: String]()
                for (key, value) in headers {
                    if let key = key as? String, let value = value as? String {
                        newHeaderFields[key] = value
                    }
                }
                
                // Add Cache-Control header for 1 hour (3600 seconds)
                newHeaderFields["Cache-Control"] = "max-age=3600"
                
                if let newResponse = HTTPURLResponse(
                    url: httpResponse.url!,
                    statusCode: httpResponse.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: newHeaderFields
                ) {
                    // Create cached response with modified headers
                    let cachedResponse = CachedURLResponse(
                        response: newResponse,
                        data: data,
                        storagePolicy: .allowed
                    )
                    
                    URLCache.shared.storeCachedResponse(cachedResponse, for: request)
                }
            }
        }
        
        let jsonDecoder = JSONDecoder()
        let elDoritoResponse: ElDoritoTokensResponse = try jsonDecoder.decode(ElDoritoTokensResponse.self, from: data)
        
        return elDoritoResponse.tokens
    }
    
    func fetchQuotes(
        chain: String,
        source: String,
        destination: String,
        amount: String,
        from: String,
        to: String,
        isAffiliate: Bool
    ) async throws -> (quote: ElDoritoQuote, fee: BigInt?) {
        
        print("💰 ElDoritoService: Fetching swap quote")
        print("💰 ElDoritoService: From asset: \(source)")
        print("💰 ElDoritoService: To asset: \(destination)")
        print("💰 ElDoritoService: Amount: \(amount)")
        print("💰 ElDoritoService: From address: \(from)")
        print("💰 ElDoritoService: To address: \(to)")
        
        let url = Endpoint.fetchElDoritoSwapQuote()
        print("💰 ElDoritoService: URL: \(url)")
        
        var body: [String: Any] = [
            "sellAsset": source, // The asset being sold (e.g. "ETH.ETH").
            "buyAsset": destination, // The asset being bought (e.g. "BTC.BTC").
            "sellAmount": amount, // Amount in basic units (decimals separated with a dot).
            "sourceAddress": from,
            "destinationAddress": to,
            "slippage": 1,
            "includeTx": true
        ]
        
        // Add affiliate parameters if enabled
        if isAffiliate {
            body["affiliate"] = "0xa4a4f610e89488eb4ecc6c63069f241a54485269"
            body["affiliateFee"] = 50 // Example: 0.5% fee
        }
        
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dataPayload
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // print(String(data: data, encoding: .utf8) ?? "No data")
        
        let response = try JSONDecoder().decode(ElDoritoResponse.self, from: data)
        print("💰 ElDoritoService: Response decoded successfully")
        print("💰 ElDoritoService: Routes count: \(response.routes.count)")
        
        var fee = BigInt(0)
        if let quote = response.routes.first {
            print("💰 ElDoritoService: Found route with fee: \(quote.fees)")

            
            if let transaction = quote.tx {
                print("💰 ElDoritoService: Transaction data available")
                print("💰 ElDoritoService: Transaction to: \(transaction.to)")
                print("💰 ElDoritoService: Transaction value: \(transaction.value)")
                print("💰 ElDoritoService: Transaction gas: \(transaction.gas ?? 0)")
                print("💰 ElDoritoService: Transaction gasPrice: \(transaction.gasPrice ?? "0")")
                
                let gasPrice = BigInt(transaction.gasPrice ?? "0") ?? 0
                let gas = BigInt(transaction.gas ?? .zero)
                fee = gas * gasPrice
                print("💰 ElDoritoService: Calculated fee: \(fee)")
            } else {
                print("💰 ElDoritoService: ⚠️ No transaction data in quote")
            }
            
            return (quote, fee)
        } else {
            print("💰 ElDoritoService: ⚠️ No routes found")
        }
        
        throw SwapError.routeUnavailable
    }

}

private extension ElDoritoService {
    struct ElDoritoTokensResponse: Codable {
        let provider: String
        let name: String
        let timestamp: String
        let version: VersionInfo
        let keywords: [String]
        let count: Int
        let tokens: [ElDoritoToken]
    }
    
    struct VersionInfo: Codable {
        let major: Int
        let minor: Int
        let patch: Int
    }
}
