//
//  JupiterCatalogRankingTests.swift
//  VultisigAppTests
//
//  Pins the Jupiter list's best-first ordering. `CatalogToken` carries no rank
//  field, so the order the provider returns IS the ranking signal — a consumer
//  that shows only the head of the list depends on it.
//

import XCTest
@testable import VultisigApp

final class JupiterCatalogRankingTests: XCTestCase {

    /// `SolanaJupiterToken` is decode-only (it models a wire payload), so the
    /// fixtures go through JSON — which also pins that `organicScore` decodes.
    private func decode(_ json: String) throws -> [SolanaJupiterToken] {
        try JSONDecoder().decode([SolanaJupiterToken].self, from: Data(json.utf8))
    }

    private func entry(_ symbol: String, organicScore: String) -> String {
        """
        { "id": "mint-\(symbol)", "name": "\(symbol)", "symbol": "\(symbol)",
          "decimals": 6, "icon": "https://logo/\(symbol).png", "organicScore": \(organicScore) }
        """
    }

    func testRanksByOrganicScoreDescending() throws {
        let entries = [
            entry("LOW", organicScore: "1.5"),
            entry("HIGH", organicScore: "99.5"),
            entry("MID", organicScore: "50")
        ]
        let tokens = try decode("[\(entries.joined(separator: ","))]")

        let ranked = SolanaJupiterToken.rankedForCatalog(tokens)

        XCTAssertEqual(ranked.map { $0.symbol }, ["HIGH", "MID", "LOW"])
    }

    func testMissingOrganicScoreRanksLastWithoutCrashing() throws {
        let missing = """
        { "id": "mint-NOSCORE", "name": "NOSCORE", "symbol": "NOSCORE", "decimals": 6 }
        """
        let tokens = try decode("[\(missing), \(entry("ZERO", organicScore: "0"))]")

        let ranked = SolanaJupiterToken.rankedForCatalog(tokens)

        XCTAssertEqual(ranked.map { $0.symbol }, ["ZERO", "NOSCORE"],
                       "A missing score ranks below even a real zero")
        XCTAssertNil(tokens.first(where: { $0.symbol == "NOSCORE" })?.organicScore)
    }

    func testTiesKeepJupitersOwnOrder() throws {
        // ~92% of the verified list scores 0. A non-stable sort would reshuffle
        // that tail between fetches, so equal scores must hold their input order.
        let tokens = try decode("[\(entry("A", organicScore: "0")), \(entry("B", organicScore: "0")), \(entry("C", organicScore: "0"))]")

        XCTAssertEqual(SolanaJupiterToken.rankedForCatalog(tokens).map { $0.symbol }, ["A", "B", "C"])
    }

    func testHighMarketCapWithoutOrganicVolumeDoesNotOutrankRealTokens() throws {
        // Why the rank is `organicScore` and not `mcap`: the live list's mcap
        // head is dominated by tokenised-equity wrappers carrying a
        // billion-dollar paper cap against four figures of liquidity, which is
        // exactly the entry a browse list must not lead with.
        let paperGiant = """
        { "id": "mint-PAPER", "name": "PAPER", "symbol": "PAPER", "decimals": 6,
          "mcap": 13404117224, "liquidity": 57469, "organicScore": 0 }
        """
        let realToken = """
        { "id": "mint-USDC", "name": "USDC", "symbol": "USDC", "decimals": 6,
          "mcap": 7779892140, "liquidity": 351575478, "organicScore": 100 }
        """
        let tokens = try decode("[\(paperGiant), \(realToken)]")

        XCTAssertEqual(SolanaJupiterToken.rankedForCatalog(tokens).map { $0.symbol }, ["USDC", "PAPER"])
    }

    // MARK: - the transform the service actually calls

    func testPayloadToCatalogMetasIsRankedAndMapped() throws {
        // Pins the ranking on the path `SolanaService.fetchSolanaJupiterTokenList`
        // uses: ranking only inside `rankedForCatalog` would let the service drop
        // the call and still pass every test above.
        let entries = [
            entry("TAIL", organicScore: "0"),
            entry("BEST", organicScore: "100")
        ]

        let metas = try SolanaJupiterToken.rankedCatalogMetas(from: Data("[\(entries.joined(separator: ","))]".utf8))

        XCTAssertEqual(metas.map { $0.ticker }, ["BEST", "TAIL"], "The payload transform ranks before mapping")
        XCTAssertEqual(metas.first?.chain, .solana)
        XCTAssertEqual(metas.first?.contractAddress, "mint-BEST")
        XCTAssertEqual(metas.first?.decimals, 6)
        XCTAssertFalse(metas.first?.isNativeToken ?? true)
    }
}
