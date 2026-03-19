import Foundation

struct SolanaJupiterToken: Codable {
    enum CodingKeys: String, CodingKey {
        case address = "id"
        case name
        case symbol
        case decimals
        case logoURI = "icon"
        case extensions
    }
    let address: String?
    let name: String?
    let symbol: String?
    let decimals: Int?
    let logoURI: String?
    let extensions: SolanaJupiterTokenExtensions?

    // Custom init to handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try? container.decode(String.self, forKey: .address)
        name = try? container.decode(String.self, forKey: .name)
        symbol = try? container.decode(String.self, forKey: .symbol)
        decimals = try? container.decode(Int.self, forKey: .decimals)
        logoURI = try? container.decode(String.self, forKey: .logoURI)
        extensions = try? container.decode(SolanaJupiterTokenExtensions.self, forKey: .extensions)
    }
}

struct SolanaJupiterTokenExtensions: Codable {
    let coingeckoId: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coingeckoId = try? container.decode(String.self, forKey: .coingeckoId)
    }
}
