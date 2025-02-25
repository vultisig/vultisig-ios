import Foundation

class SolanaJupiterToken: Codable {
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
