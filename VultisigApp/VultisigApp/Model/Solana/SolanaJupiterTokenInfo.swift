import Foundation

class SolanaJupiterToken: Codable {
    let address: String
    let name: String
    let symbol: String
    let decimals: Int
    let logoURI: URL
    
    let extensions: SolanaJupiterTokenExtensions
    
    enum CodingKeys: String, CodingKey {
        case address
        case name
        case symbol
        case decimals
        case logoURI = "logoURI"

        case extensions
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        address = try container.decode(String.self, forKey: .address)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        decimals = try container.decode(Int.self, forKey: .decimals)
        logoURI = try container.decode(URL.self, forKey: .logoURI)
        extensions = try container.decode(SolanaJupiterTokenExtensions.self, forKey: .extensions)
    }
}

class SolanaJupiterTokenExtensions: Codable {
    let coingeckoId: String
    
    enum CodingKeys: String, CodingKey {
        case coingeckoId = "coingeckoId"
    }
}

extension SolanaJupiterToken {
    static func decodeFromJSON(_ jsonData: Data) throws -> SolanaJupiterToken {
        let decoder = JSONDecoder()
        return try decoder.decode(SolanaJupiterToken.self, from: jsonData)
    }
    
    static func encodeToJSON(token: SolanaJupiterToken) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(token)
    }
}
