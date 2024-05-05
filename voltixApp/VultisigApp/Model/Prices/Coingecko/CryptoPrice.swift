import Foundation

// Define a generic struct for decoding any cryptocurrency data with any fiat currencies
class CryptoPrice: Codable {
    var prices: [String: [String: Double]]
    
    init(prices: [String: [String: Double]]){
        self.prices = prices
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var prices = [String: [String: Double]]()
        
        for key in container.allKeys {
            let value = try container.decode([String: Double].self, forKey: key)
            prices[key.stringValue] = value
        }
        
        self.prices = prices
    }
}

fileprivate class DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    
    required init?(intValue: Int) { nil }
    
    required init?(stringValue: String) {
        self.stringValue = stringValue
    }
}
