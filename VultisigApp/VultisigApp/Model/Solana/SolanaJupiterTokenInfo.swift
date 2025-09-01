import Foundation

class SolanaJupiterToken: Codable {
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
}

class SolanaJupiterTokenExtensions: Codable {
    let coingeckoId: String?
}
