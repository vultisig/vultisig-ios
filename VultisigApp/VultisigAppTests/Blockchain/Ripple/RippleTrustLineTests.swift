//
//  RippleTrustLineTests.swift
//  VultisigAppTests
//
//  Covers reading XRPL issued-currency (trust-line) token balances: the
//  paginated `account_lines` walk, the per-token balance lookup, and the
//  discovery filter that decides which lines become coins. Uses a canned-JSON
//  HTTP stub (no network, no sleeps) in the style of
//  `RippleBroadcastGatingTests` / `RippleRetryTests`.
//

@testable import VultisigApp
import XCTest

final class RippleTrustLineTests: XCTestCase {

    private static let account = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
    private static let rlusdIssuer = "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"
    private static let usdIssuer = "rvYAfWj5gh67oV6fW32ZzP3Aw4Eubs59B"
    /// 160-bit hex form of `RLUSD` — the on-ledger code for a >3-character ticker.
    private static let rlusdHex = "524C555344000000000000000000000000000000"

    // MARK: - Pagination

    func testPaginationAssemblesEveryPage() async throws {
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "1")], marker: "m1"),
            Self.linesJSON([Self.line(currency: "EUR", issuer: Self.usdIssuer, balance: "2")], marker: "m2"),
            Self.linesJSON([Self.line(currency: Self.rlusdHex, issuer: Self.rlusdIssuer, balance: "3")], marker: nil)
        ]
        let service = Self.makeService(stub)

        let lines = try await service.fetchAccountLines(for: Self.account)

        XCTAssertEqual(lines.map(\.currency), ["USD", "EUR", Self.rlusdHex])
        XCTAssertEqual(stub.callCount, 3, "a single page would have hidden two lines")
        XCTAssertEqual(stub.requestedMarkers, [nil, "m1", "m2"], "each page must resume from the previous marker")
    }

    func testFirstRequestCarriesLedgerIndexAndIgnoreDefaultAndNoMarker() async throws {
        let stub = RippleAccountLinesStub()
        stub.pages = [Self.linesJSON([], marker: nil)]
        let service = Self.makeService(stub)

        _ = try await service.fetchAccountLines(for: Self.account)

        let params = try XCTUnwrap(stub.requestedParams.first)
        XCTAssertEqual(params["account"] as? String, Self.account)
        XCTAssertEqual(params["ledger_index"] as? String, "current")
        XCTAssertEqual(params["ignore_default"] as? Bool, true)
        XCTAssertNil(params["marker"], "the first page must not send a marker key")
    }

    func testEveryPageGoesToTheHostResolvedWhenTheWalkStarted() async throws {
        // The walk pins one resolved host, so a custom-RPC change landing between
        // pages cannot stitch two networks' pages into one balance.
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "1")], marker: "m1"),
            Self.linesJSON([Self.line(currency: "EUR", issuer: Self.usdIssuer, balance: "2")], marker: nil)
        ]
        let resolver = ShiftingResolver(first: "https://first.example.com", then: "https://second.example.com")
        let service = RippleService(resolver: resolver, httpClient: stub, sleep: { _ in })

        _ = try await service.fetchAccountLines(for: Self.account)

        XCTAssertEqual(stub.requestedHosts.count, 2)
        XCTAssertEqual(
            Set(stub.requestedHosts.map(\.absoluteString)),
            ["https://first.example.com"],
            "a mid-walk custom-RPC change must not move a later page to another host"
        )
    }

    func testDuplicateLineAcrossPagesIsCollapsed() async throws {
        // Each page is served from a fresh `current` ledger, so a line can repeat
        // when the ledger advances mid-walk. The ledger holds at most one line per
        // (counterparty, currency), so the repeat must not double-count.
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "1")], marker: "m1"),
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "1")], marker: nil)
        ]
        let service = Self.makeService(stub)

        let lines = try await service.fetchAccountLines(for: Self.account)

        XCTAssertEqual(lines.count, 1)
    }

    func testActNotFoundResolvesToEmptySet() async throws {
        // An unfunded account has no AccountRoot and therefore holds no trust
        // lines — a valid outcome, not an error.
        let stub = RippleAccountLinesStub()
        stub.pages = [#"{"result":{"error":"actNotFound","status":"error"}}"#]
        let service = Self.makeService(stub)

        let lines = try await service.fetchAccountLines(for: Self.account)

        XCTAssertTrue(lines.isEmpty)
        XCTAssertEqual(stub.callCount, 1, "actNotFound is not retryable")
    }

    func testActNotFoundMidPaginationThrowsRatherThanTruncating() async {
        // Mid-walk the account was deleted under us; returning the first page (or
        // an empty set) would under-report a real balance.
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "5")], marker: "m1"),
            #"{"result":{"error":"actNotFound","status":"error"}}"#
        ]
        let service = Self.makeService(stub)

        await Self.assertThrowsTrustLineError(.accountLinesFailed(code: "actNotFound")) {
            _ = try await service.fetchAccountLines(for: Self.account)
        }
    }

    func testNonRetryableNodeErrorThrowsRatherThanReportingNoLines() async {
        let stub = RippleAccountLinesStub()
        stub.pages = [#"{"result":{"error":"invalidParams","status":"error"}}"#]
        let service = Self.makeService(stub)

        await Self.assertThrowsTrustLineError(.accountLinesFailed(code: "invalidParams")) {
            _ = try await service.fetchAccountLines(for: Self.account)
        }
    }

    func testResponseWithoutLinesArrayThrowsRatherThanReportingEmpty() async {
        // A proxy error page decoding to all-nils is not an empty wallet; reading
        // it as one would render a real token balance as zero.
        let stub = RippleAccountLinesStub()
        stub.pages = [#"{"result":{}}"#]
        let service = Self.makeService(stub)

        await Self.assertThrowsTrustLineError(.malformedResponse) {
            _ = try await service.fetchAccountLines(for: Self.account)
        }
    }

    // MARK: - Token balance

    func testTokenBalanceIsReturnedInBaseUnits() async throws {
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: Self.rlusdHex, issuer: Self.rlusdIssuer, balance: "12.5")], marker: nil)
        ]
        let service = Self.makeService(stub)

        let balance = try await service.getTokenBalance(
            coin: Self.coin(tokenId: "\(Self.rlusdHex).\(Self.rlusdIssuer)"),
            address: Self.account
        )

        // 12.5 at 15 decimals.
        XCTAssertEqual(balance, "12500000000000000")
    }

    func testNegativeBalanceReportsZeroBecauseItIsAnIssuanceLiability() async throws {
        // A negative balance means this account IS the issuer and owes the
        // counterparty. That is a liability, never a negative asset.
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "-42.5")], marker: nil)
        ]
        let service = Self.makeService(stub)

        let balance = try await service.getTokenBalance(
            coin: Self.coin(tokenId: "USD.\(Self.usdIssuer)"),
            address: Self.account
        )

        XCTAssertEqual(balance, "0")
    }

    func testBalanceIsZeroWhenNoLineMatches() async throws {
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "EUR", issuer: Self.usdIssuer, balance: "7")], marker: nil)
        ]
        let service = Self.makeService(stub)

        let balance = try await service.getTokenBalance(
            coin: Self.coin(tokenId: "USD.\(Self.usdIssuer)"),
            address: Self.account
        )

        XCTAssertEqual(balance, "0")
    }

    func testSameIssuerDifferentCurrencyDoesNotMatch() async throws {
        // XRPL keys a token by (currency, issuer): the issuer alone is not enough.
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([
                Self.line(currency: "EUR", issuer: Self.usdIssuer, balance: "7"),
                Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "3")
            ], marker: nil)
        ]
        let service = Self.makeService(stub)

        let balance = try await service.getTokenBalance(
            coin: Self.coin(tokenId: "USD.\(Self.usdIssuer)"),
            address: Self.account
        )

        XCTAssertEqual(balance, "3000000000000000")
    }

    func testSameCurrencyDifferentIssuerDoesNotMatch() async throws {
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.rlusdIssuer, balance: "9")], marker: nil)
        ]
        let service = Self.makeService(stub)

        let balance = try await service.getTokenBalance(
            coin: Self.coin(tokenId: "USD.\(Self.usdIssuer)"),
            address: Self.account
        )

        XCTAssertEqual(balance, "0")
    }

    func testIssuerMatchingIsCaseSensitive() async throws {
        // XRPL issuer addresses are base58, where case is significant. Relaxing
        // the comparison to case-insensitive would conflate two distinct issuers.
        let miscased = Self.usdIssuer.lowercased()
        XCTAssertNotEqual(miscased, Self.usdIssuer, "the fixture must actually differ by case")

        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: miscased, balance: "9")], marker: nil)
        ]
        let service = Self.makeService(stub)

        let balance = try await service.getTokenBalance(
            coin: Self.coin(tokenId: "USD.\(Self.usdIssuer)"),
            address: Self.account
        )

        XCTAssertEqual(balance, "0")
    }

    func testLowercaseHexCurrencyFromNodeMatchesUppercaseTokenId() async throws {
        // Both sides go through `toXrplCurrencyCode`, so a node spelling a
        // non-standard code in lowercase still resolves to the stored coin.
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([
                Self.line(currency: Self.rlusdHex.lowercased(), issuer: Self.rlusdIssuer, balance: "4")
            ], marker: nil)
        ]
        let service = Self.makeService(stub)

        let balance = try await service.getTokenBalance(
            coin: Self.coin(tokenId: "\(Self.rlusdHex).\(Self.rlusdIssuer)"),
            address: Self.account
        )

        XCTAssertEqual(balance, "4000000000000000")
    }

    func testStandardThreeCharacterCurrencyMatchesVerbatim() async throws {
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "1.25")], marker: nil)
        ]
        let service = Self.makeService(stub)

        let balance = try await service.getTokenBalance(
            coin: Self.coin(tokenId: "USD.\(Self.usdIssuer)"),
            address: Self.account
        )

        XCTAssertEqual(balance, "1250000000000000")
    }

    func testMalformedTokenIdThrows() async {
        let stub = RippleAccountLinesStub()
        stub.pages = [Self.linesJSON([], marker: nil)]
        let service = Self.makeService(stub)

        do {
            _ = try await service.getTokenBalance(coin: Self.coin(tokenId: "USD"), address: Self.account)
            XCTFail("Expected a token id without an issuer to throw")
        } catch RippleIssuedCurrency.ParseError.invalidTokenId {
            XCTAssertEqual(stub.callCount, 0, "the id is rejected before any network call")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Currency code <-> ticker

    func testToXrplCurrencyCodeDerivesRlusdHexFromAsciiBytes() throws {
        // Derived here rather than transcribed: ASCII bytes right-padded to 20.
        let expected = (Array("RLUSD".utf8) + Array(repeating: UInt8(0), count: 15))
            .map { String(format: "%02X", $0) }
            .joined()

        XCTAssertEqual(expected.count, 40)
        XCTAssertEqual(try RippleIssuedCurrency.toXrplCurrencyCode("RLUSD"), expected)
        XCTAssertEqual(Self.rlusdHex, expected, "the fixture must match the derived code")
    }

    func testHexCurrencyDecodesToItsAsciiTicker() {
        XCTAssertEqual(RippleIssuedCurrency.toIssuedCurrencyTicker(Self.rlusdHex), "RLUSD")
    }

    func testTickerRoundTripsThroughCurrencyCode() throws {
        let code = try RippleIssuedCurrency.toXrplCurrencyCode("RLUSD")
        XCTAssertEqual(RippleIssuedCurrency.toIssuedCurrencyTicker(code), "RLUSD")
    }

    func testNonPrintableHexCurrencyStaysHex() {
        // A 160-bit code that is not packed ASCII must not be rendered as mojibake.
        let opaque = "0158415500000000C1F76FF6ECB0BAC600000000"
        XCTAssertEqual(RippleIssuedCurrency.toIssuedCurrencyTicker(opaque), opaque)
    }

    func testAllZeroHexCurrencyStaysHex() {
        let zeros = String(repeating: "0", count: 40)
        XCTAssertEqual(RippleIssuedCurrency.toIssuedCurrencyTicker(zeros), zeros)
    }

    func testStandardCurrencyCodeIsNotTouched() {
        XCTAssertEqual(RippleIssuedCurrency.toIssuedCurrencyTicker("USD"), "USD")
    }

    func testAsciiPackedHexOfAThreeCharacterTickerIsADistinctCurrency() throws {
        // XRPL encodes a standard code as ASCII at bytes 12-14 with a 0x00 first
        // byte, so the ASCII-PACKED hex of "USD" is a different, non-standard
        // currency. `toXrplCurrencyCode` passes 3-character codes through
        // untouched for exactly that reason — do not "normalize" them to hex.
        let packed = (Array("USD".utf8) + Array(repeating: UInt8(0), count: 17))
            .map { String(format: "%02X", $0) }
            .joined()

        XCTAssertEqual(try RippleIssuedCurrency.toXrplCurrencyCode("USD"), "USD")
        XCTAssertNotEqual(try RippleIssuedCurrency.toXrplCurrencyCode(packed), "USD")
    }

    func testRippleTokenIdRoundTripsThroughParse() throws {
        let id = try RippleIssuedCurrency.rippleTokenId(currency: "RLUSD", issuer: Self.rlusdIssuer)
        let (currency, issuer) = try RippleIssuedCurrency.parseRippleTokenId(id)

        XCTAssertEqual(currency, Self.rlusdHex)
        XCTAssertEqual(issuer, Self.rlusdIssuer)
    }

    // MARK: - Discovery filter

    func testDiscoveryExcludesZeroAndNegativeBalances() {
        let lines = [
            Self.decodedLine(currency: "USD", issuer: Self.usdIssuer, balance: "5"),
            Self.decodedLine(currency: "EUR", issuer: Self.usdIssuer, balance: "0"),
            Self.decodedLine(currency: "GBP", issuer: Self.usdIssuer, balance: "-3")
        ]

        let tokens = RippleTrustLineTokens.discoverableTokens(from: lines)

        XCTAssertEqual(tokens.map(\.ticker), ["USD"], "only a strictly positive balance is a holding")
    }

    func testDiscoveryKeepsADustBalance() {
        // Strictly positive means strictly positive, not "big enough to notice".
        let lines = [Self.decodedLine(currency: "USD", issuer: Self.usdIssuer, balance: "0.000000000000001")]

        XCTAssertEqual(RippleTrustLineTokens.discoverableTokens(from: lines).count, 1)
    }

    func testDiscoveryTruncatesBelowModelledPrecisionToZeroAndExcludesIt() {
        // Below 15 decimals the value truncates to zero base units, so it is not
        // a holding we can represent.
        let lines = [Self.decodedLine(currency: "USD", issuer: Self.usdIssuer, balance: "1e-16")]

        XCTAssertTrue(RippleTrustLineTokens.discoverableTokens(from: lines).isEmpty)
    }

    func testDiscoveryDerivesTickerAndTokenIdFromTheLine() {
        let lines = [Self.decodedLine(currency: "USD", issuer: Self.usdIssuer, balance: "5")]

        let token = RippleTrustLineTokens.discoverableTokens(from: lines).first

        XCTAssertEqual(token?.chain, .ripple)
        XCTAssertEqual(token?.ticker, "USD")
        XCTAssertEqual(token?.contractAddress, "USD.\(Self.usdIssuer)")
        XCTAssertEqual(token?.decimals, RippleIssuedCurrency.issuedCurrencyDecimals)
        XCTAssertEqual(token?.isNativeToken, false)
    }

    func testDiscoveryKeepsOpaqueHexCurrencyAsItsTicker() {
        let opaque = "0158415500000000C1F76FF6ECB0BAC600000000"
        let lines = [Self.decodedLine(currency: opaque, issuer: Self.usdIssuer, balance: "5")]

        XCTAssertEqual(RippleTrustLineTokens.discoverableTokens(from: lines).first?.ticker, opaque)
    }

    func testDiscoverySkipsALineWithAnUnparseableBalance() {
        let lines = [
            Self.decodedLine(currency: "USD", issuer: Self.usdIssuer, balance: "not-a-number"),
            Self.decodedLine(currency: "EUR", issuer: Self.usdIssuer, balance: "1")
        ]

        XCTAssertEqual(RippleTrustLineTokens.discoverableTokens(from: lines).map(\.ticker), ["EUR"])
    }

    func testCuratedTokensStoreEntryWinsOverLineDerivedMetadata() throws {
        let lines = [Self.decodedLine(currency: Self.rlusdHex, issuer: Self.rlusdIssuer, balance: "10")]

        let token = try XCTUnwrap(RippleTrustLineTokens.discoverableTokens(from: lines).first)

        XCTAssertEqual(token.ticker, "RLUSD")
        // The line carries no price provider; only the curated entry does.
        XCTAssertEqual(token.priceProviderId, "ripple-usd")
        XCTAssertEqual(token.decimals, 15)
    }

    // MARK: - Curated RLUSD entry

    func testCuratedRlusdEntryMatchesTheOnLedgerTokenId() throws {
        let curated = try XCTUnwrap(TokensStore.TokenSelectionAssets.first {
            $0.chain == .ripple && $0.ticker == "RLUSD"
        })

        let (currency, issuer) = try RippleIssuedCurrency.parseRippleTokenId(curated.contractAddress)
        XCTAssertEqual(currency, try RippleIssuedCurrency.toXrplCurrencyCode("RLUSD"))
        XCTAssertEqual(issuer, Self.rlusdIssuer)
        XCTAssertEqual(curated.decimals, RippleIssuedCurrency.issuedCurrencyDecimals)
        XCTAssertEqual(curated.priceProviderId, "ripple-usd")
        XCTAssertFalse(curated.isNativeToken)
    }

    func testCuratedRlusdEntryIsFoundByTokenIdLookup() throws {
        let tokenId = try RippleIssuedCurrency.rippleTokenId(currency: "RLUSD", issuer: Self.rlusdIssuer)

        let found = TokensStore.findTokenMeta(chain: .ripple, contractAddress: tokenId)

        XCTAssertEqual(found?.ticker, "RLUSD")
    }

    // MARK: - The curated XRPL catalog as a whole

    /// Every curated XRPL entry must be a well-formed, resolvable token id. A
    /// typo in an issuer or a currency code here is invisible until a user's
    /// balance silently reads zero, because the lookup simply fails to match.
    func testEveryCuratedRippleTokenHasAWellFormedTokenId() throws {
        for curated in Self.curatedRippleTokens {
            let (currency, issuer) = try RippleIssuedCurrency.parseRippleTokenId(curated.contractAddress)

            XCTAssertTrue(
                AddressService.validateAddress(address: issuer, chain: .ripple),
                "\(curated.ticker) has an issuer that is not a valid XRPL address"
            )
            XCTAssertEqual(
                currency,
                try RippleIssuedCurrency.toXrplCurrencyCode(currency),
                "\(curated.ticker) currency is not in its normalized on-ledger form"
            )
            XCTAssertFalse(curated.isNativeToken, "\(curated.ticker) must not be native")
            XCTAssertEqual(
                curated.decimals,
                RippleIssuedCurrency.issuedCurrencyDecimals,
                "\(curated.ticker) must use the 15-digit issued-currency scale"
            )
        }
    }

    /// A curated entry exists to supply the two things the ledger cannot: a
    /// price feed and a logo. One without a `priceProviderId` would render a
    /// blank fiat column, which is what auto-discovery already does for free —
    /// so it would be carrying no weight.
    func testEveryCuratedRippleTokenCarriesAPriceProviderAndALogo() {
        for curated in Self.curatedRippleTokens {
            XCTAssertFalse(
                curated.priceProviderId.isEmpty,
                "\(curated.ticker) has no priceProviderId, so it would show no fiat value"
            )
            XCTAssertTrue(
                curated.logo.hasPrefix("https://"),
                "\(curated.ticker) logo must be a remote URL — no XRPL token art is bundled"
            )
        }
    }

    /// `CoinMeta.uniqueId` keys on `chain-ticker-contractAddress`, so two
    /// curated rows sharing a ticker would be two coins a user cannot tell
    /// apart. This is the guard against curating gateway IOUs (two issuers both
    /// tickered `USD`) without first fixing identity to be contract-keyed.
    func testCuratedRippleTickersAreUnique() {
        let tickers = Self.curatedRippleTokens.map { $0.ticker.lowercased() }

        XCTAssertEqual(Set(tickers).count, tickers.count, "duplicate curated XRPL ticker: \(tickers)")
    }

    /// The on-ledger currency for Equilibrium decodes to `Equilibrium`, not to
    /// the `EQ` the curated entry uses. Discovery must therefore return the
    /// curated row verbatim rather than deriving its own ticker — otherwise the
    /// same trust line yields two different `uniqueId`s and shows up twice.
    func testCuratedTickerWinsOverTheDecodedCurrencyForEquilibrium() throws {
        let curated = try XCTUnwrap(TokensStore.TokenSelectionAssets.first {
            $0.chain == .ripple && $0.ticker == "EQ"
        })
        let (currency, issuer) = try RippleIssuedCurrency.parseRippleTokenId(curated.contractAddress)
        XCTAssertEqual(
            RippleIssuedCurrency.toIssuedCurrencyTicker(currency),
            "Equilibrium",
            "precondition: the ledger code decodes to the long name"
        )

        let discovered = RippleTrustLineTokens.discoverableTokens(
            from: [Self.decodedLine(currency: currency, issuer: issuer, balance: "5")]
        )

        XCTAssertEqual(discovered.map(\.ticker), ["EQ"])
        XCTAssertEqual(discovered.first?.uniqueId, curated.uniqueId)
    }

    /// Pins each curated token id to the currency and issuer it is supposed to
    /// name. The well-formedness test above would happily accept a typo — any
    /// 40 hex digits normalize to themselves — and a wrong digit here does not
    /// fail loudly: the trust line simply never matches and the balance reads
    /// zero forever. So the decoded ticker and the issuer are both asserted.
    func testEveryCuratedRippleTokenDecodesToTheCurrencyItClaims() throws {
        let expected: [String: (ticker: String, issuer: String)] = [
            "RLUSD": ("RLUSD", "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"),
            "SOLO": ("SOLO", "rsoLo2S1kiGeCcn6hCUXVrCpGMWLrRrLZz"),
            "USDC": ("USDC", "rGm7WCVp9gb4jZHWTEtGUr4dd74z2XuWhE"),
            // The on-ledger code is the ASCII packing of the full name, not of
            // the "EQ" the entry is tickered with.
            "EQ": ("Equilibrium", "rpakCr61Q92abPXJnVboKENmpKssWyHpwu")
        ]

        XCTAssertEqual(
            Set(Self.curatedRippleTokens.map(\.ticker)),
            Set(expected.keys),
            "the curated XRPL set changed — update the expectations rather than the assertion"
        )

        for curated in Self.curatedRippleTokens {
            let want = try XCTUnwrap(expected[curated.ticker])
            let (currency, issuer) = try RippleIssuedCurrency.parseRippleTokenId(curated.contractAddress)

            XCTAssertEqual(
                RippleIssuedCurrency.toIssuedCurrencyTicker(currency),
                want.ticker,
                "\(curated.ticker) currency code does not decode to \(want.ticker)"
            )
            XCTAssertEqual(issuer, want.issuer, "\(curated.ticker) has the wrong issuer")
        }
    }

    private static var curatedRippleTokens: [CoinMeta] {
        TokensStore.TokenSelectionAssets.filter { $0.chain == .ripple && !$0.isNativeToken }
    }

    // MARK: - BalanceService routing

    func testBalanceServiceRoutesANonNativeCoinToItsTrustLineBalance() async throws {
        // The bug this pins: before the isNativeToken branch, `.ripple` returned
        // the account's XRP balance for a token row too.
        let stub = RippleAccountLinesStub()
        stub.pages = [
            Self.linesJSON([Self.line(currency: "USD", issuer: Self.usdIssuer, balance: "7")], marker: nil)
        ]
        stub.accountInfoJSON = Self.accountInfoJSON
        let balanceService = BalanceService(ripple: Self.makeService(stub))

        let balance = try await balanceService.fetchBalance(
            for: Self.coin(tokenId: "USD.\(Self.usdIssuer)"),
            address: Self.account
        )

        XCTAssertEqual(balance, "7000000000000000", "must be the token balance, not the XRP balance")
        XCTAssertEqual(stub.requestedMethods, ["account_lines"])
    }

    func testBalanceServiceRoutesTheNativeCoinToTheAccountBalance() async throws {
        let stub = RippleAccountLinesStub()
        stub.accountInfoJSON = Self.accountInfoJSON
        stub.serverStateJSON = Self.serverStateJSON
        let balanceService = BalanceService(ripple: Self.makeService(stub))

        let balance = try await balanceService.fetchBalance(for: Self.nativeXRP, address: Self.account)

        // 5 XRP held minus the 1 XRP base reserve, in drops.
        XCTAssertEqual(balance, "4000000")
        XCTAssertFalse(
            stub.requestedMethods.contains("account_lines"),
            "the native balance must not read trust lines"
        )
    }

    // MARK: - Registry wiring

    @MainActor
    func testRippleResolvesToTheTrustLineDiscoverer() {
        XCTAssertTrue(
            TokenDiscovererRegistry.discoverer(for: .ripple) is RippleTrustLineTokenDiscoverer,
            "XRP token discovery must no longer be a no-op"
        )
    }

    // MARK: - Helpers

    private static func makeService(_ stub: RippleAccountLinesStub) -> RippleService {
        RippleService(resolver: NoOverrideResolver(), httpClient: stub, sleep: { _ in })
    }

    /// 5 XRP held, no owned objects.
    private static let accountInfoJSON = #"""
    {"result":{"account_data":{"Account":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","Balance":"5000000","OwnerCount":0}}}
    """#

    /// Mainnet reserve values: 1 XRP base, 0.2 XRP per owned object.
    private static let serverStateJSON = #"""
    {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":1000000,"reserve_inc":200000}}}}
    """#

    private static let nativeXRP = CoinMeta(
        chain: .ripple,
        ticker: "XRP",
        logo: "xrp",
        decimals: 6,
        priceProviderId: "ripple",
        contractAddress: "",
        isNativeToken: true
    )

    private static func coin(tokenId: String) -> CoinMeta {
        CoinMeta(
            chain: .ripple,
            ticker: "TEST",
            logo: .empty,
            decimals: RippleIssuedCurrency.issuedCurrencyDecimals,
            priceProviderId: .empty,
            contractAddress: tokenId,
            isNativeToken: false
        )
    }

    private static func line(currency: String, issuer: String, balance: String) -> [String: Any] {
        [
            "account": issuer,
            "balance": balance,
            "currency": currency,
            "limit": "1000000000",
            "no_ripple": false,
            "freeze": false
        ]
    }

    /// A `RippleTrustLine` built by decoding the same JSON shape the service sees,
    /// so the discovery tests exercise the real decoder rather than a hand-rolled
    /// value.
    private static func decodedLine(currency: String, issuer: String, balance: String) -> RippleTrustLine {
        let json = linesJSON([line(currency: currency, issuer: issuer, balance: balance)], marker: nil)
        // swiftlint:disable:next force_try
        let response = try! JSONDecoder().decode(RippleAccountLinesResponse.self, from: Data(json.utf8))
        guard let decoded = response.result?.lines?.first else {
            fatalError("Failed to build a RippleTrustLine fixture")
        }
        return decoded
    }

    private static func linesJSON(_ lines: [[String: Any]], marker: String?) -> String {
        var result: [String: Any] = ["lines": lines, "account": account, "ledger_current_index": 100]
        if let marker {
            result["marker"] = marker
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["result": result]),
              let json = String(data: data, encoding: .utf8) else {
            fatalError("Failed to build an account_lines fixture")
        }
        return json
    }

    private static func assertThrowsTrustLineError(
        _ expected: RippleTrustLineError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as RippleTrustLineError {
            XCTAssertEqual(error.errorDescription, expected.errorDescription, file: file, line: line)
        } catch {
            XCTFail("Expected RippleTrustLineError, got \(error)", file: file, line: line)
        }
    }
}

// MARK: - Test doubles

/// Resolver that never overrides — the service falls back to the default host.
private struct NoOverrideResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

/// Resolver whose override changes after the first read, simulating a custom-RPC
/// change landing partway through a paginated walk.
private final class ShiftingResolver: RPCEndpointResolving, @unchecked Sendable {
    private let firstHost: String
    private let laterHost: String
    private var reads = 0

    init(first: String, then later: String) {
        firstHost = first
        laterHost = later
    }

    func url(for _: Chain) -> String? {
        reads += 1
        return reads == 1 ? firstHost : laterHost
    }
}

/// Serves canned XRPL bodies keyed on the RPC method in the encoded request, and
/// records the host, method and params of every request — every XRPL call posts
/// to `/`, so the method in the body is the only discriminator.
private final class RippleAccountLinesStub: HTTPClientProtocol, @unchecked Sendable {

    enum StubError: Error {
        case unexpectedMethod(String?)
        case exhausted
    }

    // Canned bodies: written by the test before the exercise phase, only read
    // once requests start — same arrangement as the sibling XRPL stubs.

    /// Consumed one per `account_lines` call, in order.
    var pages: [String] = []
    /// Served for every `account_info` call.
    var accountInfoJSON: String?
    /// Served for every `server_state` call.
    var serverStateJSON: String?

    /// `RippleService.getBalance` fans `account_info` and `server_state` out
    /// concurrently (`async let`), so two `request(_:)` calls land at once and
    /// every recorded field is appended to from both. Concurrent `append` is
    /// undefined behaviour, so recording goes through a lock — the same
    /// discipline the other XRPL stubs use for their counters.
    private let lock = NSLock()
    private var recordedCallCount = 0
    private var recordedParams: [[String: Any]] = []
    private var recordedMethods: [String] = []
    private var recordedHosts: [URL] = []

    var callCount: Int { lock.withLock { recordedCallCount } }
    var requestedParams: [[String: Any]] { lock.withLock { recordedParams } }
    var requestedMethods: [String] { lock.withLock { recordedMethods } }
    var requestedHosts: [URL] { lock.withLock { recordedHosts } }

    var requestedMarkers: [String?] {
        requestedParams.map { $0["marker"] as? String }
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        let method = Self.rpcMethod(of: target)
        let page = record(method: method, host: target.baseURL, params: Self.firstParams(of: target) ?? [:])

        switch method {
        case "account_lines":
            guard let page, page < pages.count else { throw StubError.exhausted }
            return HTTPResponse(data: Data(pages[page].utf8), response: Self.ok)
        case "account_info":
            guard let accountInfoJSON else { throw StubError.unexpectedMethod(method) }
            return HTTPResponse(data: Data(accountInfoJSON.utf8), response: Self.ok)
        case "server_state":
            guard let serverStateJSON else { throw StubError.unexpectedMethod(method) }
            return HTTPResponse(data: Data(serverStateJSON.utf8), response: Self.ok)
        default:
            throw StubError.unexpectedMethod(method)
        }
    }

    /// Records one request and, for `account_lines`, claims the next page index —
    /// all in one critical section, so two concurrent calls can neither interleave
    /// an `append` nor be handed the same page. `nil` for every other method.
    private func record(method: String?, host: URL, params: [String: Any]) -> Int? {
        lock.withLock { () -> Int? in
            recordedMethods.append(method ?? "")
            recordedHosts.append(host)
            guard method == "account_lines" else { return nil }
            recordedCallCount += 1
            recordedParams.append(params)
            return recordedCallCount - 1
        }
    }

    private static func body(of target: TargetType) -> [String: Any]? {
        guard case let .requestCodable(body, _) = target.task,
              let data = try? JSONEncoder().encode(body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func rpcMethod(of target: TargetType) -> String? {
        body(of: target)?["method"] as? String
    }

    private static func firstParams(of target: TargetType) -> [String: Any]? {
        (body(of: target)?["params"] as? [[String: Any]])?.first
    }

    private static let ok = HTTPURLResponse(
        url: RippleAPI.defaultHost,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}
