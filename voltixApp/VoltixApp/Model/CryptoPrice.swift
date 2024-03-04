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
}

fileprivate struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    
    init?(intValue: Int) { nil }
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
}
