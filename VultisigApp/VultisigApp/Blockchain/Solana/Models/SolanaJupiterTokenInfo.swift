import Foundation

struct SolanaJupiterToken: Codable {
    enum CodingKeys: String, CodingKey {
        case address = "id"
        case name
        case symbol
        case decimals
        case logoURI = "icon"
        case extensions
        case organicScore
    }
    let address: String?
    let name: String?
    let symbol: String?
    let decimals: Int?
    let logoURI: String?
    let extensions: SolanaJupiterTokenExtensions?
    /// Jupiter's own 0–100 token-quality metric, blending organic (non-wash)
    /// volume, holder distribution and liquidity depth. Present on every entry of
    /// the verified tag list — see `rankedForCatalog` for why it, and not `mcap`,
    /// is what the catalog ranks by.
    let organicScore: Double?

    // Custom init to handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try? container.decode(String.self, forKey: .address)
        name = try? container.decode(String.self, forKey: .name)
        symbol = try? container.decode(String.self, forKey: .symbol)
        decimals = try? container.decode(Int.self, forKey: .decimals)
        logoURI = try? container.decode(String.self, forKey: .logoURI)
        extensions = try? container.decode(SolanaJupiterTokenExtensions.self, forKey: .extensions)
        organicScore = try? container.decode(Double.self, forKey: .organicScore)
    }
}

extension SolanaJupiterToken {
    /// The whole tag-list payload → catalog transform: decode, rank best-first,
    /// map to `CoinMeta`. One place so the ranking can't be bypassed on the path
    /// the catalog provider actually uses, and so a test can pin that it isn't.
    static func rankedCatalogMetas(from data: Data) throws -> [CoinMeta] {
        let tokens = try JSONDecoder().decode([SolanaJupiterToken].self, from: data)
        return rankedForCatalog(tokens).map { $0.toCoinMeta() }
    }

    func toCoinMeta() -> CoinMeta {
        CoinMeta(
            chain: .solana,
            ticker: symbol ?? "",
            logo: logoURI ?? "",
            decimals: decimals ?? 0,
            priceProviderId: extensions?.coingeckoId ?? "",
            contractAddress: address ?? "",
            isNativeToken: false
        )
    }

    /// A missing `organicScore` sorts below every real one. The live score is
    /// bounded to 0...100, so -1 is unreachable from the wire.
    private var catalogRank: Double { organicScore ?? -1 }

    /// The Jupiter list ordered best-first, so a consumer that shows only the
    /// head of it (the token picker's browse list) shows the tokens worth
    /// showing. Jupiter returns the list in no useful order.
    ///
    /// Ranked by `organicScore` rather than `mcap`: market cap is present on only
    /// ~66% of the list and rewards paper valuation over tradability, so its head
    /// fills with high-mcap/no-liquidity mirages — tokenised-equity wrappers with
    /// a billion-dollar cap and four figures of liquidity outrank ETH and USDT.
    /// `organicScore` is on 100% of entries and its head is the tokens a user
    /// would actually recognise and trade.
    ///
    /// Stable: ties (the ~92% of the list scoring 0) keep Jupiter's own order
    /// rather than being shuffled between fetches.
    static func rankedForCatalog(_ tokens: [SolanaJupiterToken]) -> [SolanaJupiterToken] {
        tokens
            .enumerated()
            .sorted { lhs, rhs in
                guard lhs.element.catalogRank != rhs.element.catalogRank else {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.catalogRank > rhs.element.catalogRank
            }
            .map(\.element)
    }
}

struct SolanaJupiterTokenExtensions: Codable {
    let coingeckoId: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coingeckoId = try? container.decode(String.self, forKey: .coingeckoId)
    }
}
