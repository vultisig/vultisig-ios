import Foundation

class SolanaJupiterToken: Codable {
    let address: String
    let name: String
    let symbol: String
    let decimals: Int
    let logoURI: URL
    let tags: [String]
    let dailyVolume: String?
    let createdAt: Date
    let freezeAuthority: String?
    let mintAuthority: String?
    let permanentDelegate: String?
    let mintedAt: Date
    let extensions: SolanaJupiterTokenExtensions
    
    enum CodingKeys: String, CodingKey {
        case address
        case name
        case symbol
        case decimals
        case logoURI = "logoURI"
        case tags
        case dailyVolume = "daily_volume"
        case createdAt = "created_at"
        case freezeAuthority = "freeze_authority"
        case mintAuthority = "mint_authority"
        case permanentDelegate = "permanent_delegate"
        case mintedAt = "minted_at"
        case extensions
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        address = try container.decode(String.self, forKey: .address)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        decimals = try container.decode(Int.self, forKey: .decimals)
        logoURI = try container.decode(URL.self, forKey: .logoURI)
        tags = try container.decode([String].self, forKey: .tags)
        dailyVolume = try container.decodeIfPresent(String.self, forKey: .dailyVolume)
        freezeAuthority = try container.decodeIfPresent(String.self, forKey: .freezeAuthority)
        mintAuthority = try container.decodeIfPresent(String.self, forKey: .mintAuthority)
        permanentDelegate = try container.decodeIfPresent(String.self, forKey: .permanentDelegate)
        extensions = try container.decode(SolanaJupiterTokenExtensions.self, forKey: .extensions)
        
        // Custom date decoding
        let createdAtStringOrDouble = try container.decode(StringOrDouble.self, forKey: .createdAt)
        createdAt = createdAtStringOrDouble.date
        
        let mintedAtStringOrDouble = try container.decode(StringOrDouble.self, forKey: .mintedAt)
        mintedAt = mintedAtStringOrDouble.date
    }
}

class SolanaJupiterTokenExtensions: Codable {
    let coingeckoId: String
    
    enum CodingKeys: String, CodingKey {
        case coingeckoId = "coingeckoId"
    }
}

enum StringOrDouble: Codable {
    case string(String)
    case double(Double)
    
    var date: Date {
        switch self {
        case .string(let dateString):
            // Try to decode as an ISO8601 date string
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: dateString) {
                return date
            } else {
                // Fallback if the date string is invalid
                return Date()
            }
        case .double(let timestamp):
            return Date(timeIntervalSince1970: timestamp)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else {
            throw DecodingError.typeMismatch(StringOrDouble.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Double for date"))
        }
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
