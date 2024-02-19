import Foundation

// Define a generic struct for decoding any cryptocurrency data with any fiat currencies
struct CryptoPrice: Codable {
    var prices: [String: [String: Double]]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var prices = [String: [String: Double]]()
        
        for key in container.allKeys {
            let value = try container.decode([String: Double].self, forKey: key)
            prices[key.stringValue] = value
        }
        
        self.prices = prices
    }
    
    // Nested struct to handle dynamic keys
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}
