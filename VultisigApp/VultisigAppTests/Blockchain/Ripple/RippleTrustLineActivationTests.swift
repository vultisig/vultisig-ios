//
//  RippleTrustLineActivationTests.swift
//  VultisigAppTests
//
//  Covers the #4757 add-token / activate surfaces that sit around the signing
//  path: validating a user-typed XRPL token id, deciding which token rows need an
//  `Activate` affordance, quoting the owner-reserve cost, and the trust-line rows
//  a co-signer is shown instead of Payment framing.
//
//  Canned-JSON HTTP stub, no network and no sleeps, in the style of
//  `RippleTrustLineTests`.
//

@testable import VultisigApp
import BigInt
import VultisigCommonData
import XCTest

final class RippleTrustLineActivationTests: XCTestCase {

    private static let account = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
    private static let issuer = "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"
    private static let otherIssuer = "rvYAfWj5gh67oV6fW32ZzP3Aw4Eubs59B"
    /// 160-bit hex form of `RLUSD` — the on-ledger code for a >3-character ticker.
    private static let rlusdHex = "524C555344000000000000000000000000000000"

    // MARK: - Custom-token resolver: validation

    /// A valid id is `<on-ledger currency>.<XRPL issuer address>`.
    func testValidTokenIdsAreAccepted() {
        for input in [
            "USD.\(Self.issuer)",
            "EUR.\(Self.otherIssuer)",
            "\(Self.rlusdHex).\(Self.issuer)",
            // Hex codes are accepted case-insensitively and normalized later.
            "\(Self.rlusdHex.lowercased()).\(Self.issuer)",
            // Surrounding whitespace is trimmed (pasted input).
            "  USD.\(Self.issuer)  "
        ] {
            XCTAssertTrue(RippleCustomTokenResolver.isValidInput(input), "'\(input)' should be valid")
        }
    }

    /// A bare ticker longer than 3 characters is NOT a valid on-ledger code. It is
    /// only valid once normalized to the 40-char hex form — which is how the
    /// curated catalog spells it — so accepting the bare spelling here would let
    /// the same token be added twice under two different ids.
    func testUnnormalizedTickerIsRejected() {
        XCTAssertFalse(RippleCustomTokenResolver.isValidInput("RLUSD.\(Self.issuer)"))
        XCTAssertFalse(RippleCustomTokenResolver.isValidInput("USDC.\(Self.issuer)"))
    }

    /// `XRP` is reserved for the native asset and can never name an issued
    /// currency, so it must not resolve to a token.
    func testNativeXrpCurrencyCodeIsRejected() {
        XCTAssertFalse(RippleCustomTokenResolver.isValidInput("XRP.\(Self.issuer)"))
        XCTAssertFalse(RippleCustomTokenResolver.isValidInput("xrp.\(Self.issuer)"))
    }

    func testMalformedTokenIdsAreRejected() {
        for input in [
            "",
            "USD",
            "USD.",
            ".\(Self.issuer)",
            // Issuer must be a real XRPL address.
            "USD.not-an-address",
            "USD.0x0000000000000000000000000000000000000000",
            // A 4-char code is neither a standard nor a hex code.
            "USDT.\(Self.issuer)",
            // 39 hex characters — one short of the 160-bit form.
            "\(String(repeating: "A", count: 39)).\(Self.issuer)",
            // 40 characters but not hex.
            "\(String(repeating: "Z", count: 40)).\(Self.issuer)"
        ] {
            XCTAssertFalse(RippleCustomTokenResolver.isValidInput(input), "'\(input)' should be rejected")
        }
    }

    // MARK: - Custom-token resolver: resolution

    /// XRPL has no on-ledger token metadata registry, so decimals are always 15
    /// (the significant-digit scale the SDK fixes) and the ticker is decoded back
    /// out of the currency code — nothing is fetched.
    func testResolveDerivesTickerAndFixedDecimalsWithoutNetwork() throws {
        let meta = try RippleCustomTokenResolver.resolve(input: "USD.\(Self.issuer)")

        XCTAssertEqual(meta.chain, .ripple)
        XCTAssertEqual(meta.ticker, "USD")
        XCTAssertEqual(meta.decimals, RippleIssuedCurrency.issuedCurrencyDecimals)
        XCTAssertEqual(meta.decimals, 15)
        XCTAssertEqual(meta.contractAddress, "USD.\(Self.issuer)")
        XCTAssertFalse(meta.isNativeToken)
    }

    /// A hex currency code resolves to its human ticker, and the stored id keeps
    /// the UPPERCASE hex form so two spellings can't become two coins.
    func testResolveNormalizesHexCurrencyAndDecodesTicker() throws {
        let meta = try RippleCustomTokenResolver.resolve(input: "\(Self.rlusdHex.lowercased()).\(Self.issuer)")

        XCTAssertEqual(meta.ticker, "RLUSD")
        XCTAssertEqual(meta.contractAddress, "\(Self.rlusdHex).\(Self.issuer)")
    }

    /// A curated `TokensStore` entry wins: it carries the bundled logo and a
    /// working `priceProviderId`, neither of which the ledger can supply.
    func testResolvePrefersCuratedTokensStoreEntry() throws {
        let curated = try XCTUnwrap(
            TokensStore.TokenSelectionAssets.first { $0.chain == .ripple && $0.ticker == "RLUSD" },
            "the curated RLUSD entry is expected to exist"
        )

        let meta = try RippleCustomTokenResolver.resolve(input: curated.contractAddress)

        XCTAssertEqual(meta.ticker, curated.ticker)
        XCTAssertEqual(meta.priceProviderId, curated.priceProviderId)
        XCTAssertEqual(meta.contractAddress, curated.contractAddress)
    }

    func testResolveThrowsOnMalformedInput() {
        XCTAssertThrowsError(try RippleCustomTokenResolver.resolve(input: "RLUSD.\(Self.issuer)"))
        XCTAssertThrowsError(try RippleCustomTokenResolver.resolve(input: "not-a-token-id"))
    }

    /// A trust line costs an owner reserve on the XRP account that holds it, so
    /// the flow must require the vault to have XRP enabled.
    func testResolverRequiresTheVaultNativeCoin() {
        XCTAssertTrue(RippleCustomTokenResolver.requiresVaultNativeCoin)
    }

    // MARK: - Trust-line presence (the Activate affordance)

    /// The presence check reads the lines the balance refresh already fetched —
    /// it must add NO request of its own, or a token list would cost one
    /// `account_lines` call per row.
    func testTrustLinePresenceReusesTheBalanceRefreshResultWithoutANewRequest() async throws {
        let stub = RippleTrustLineStub()
        stub.pages = [Self.linesJSON([Self.line(currency: "USD", issuer: Self.issuer, balance: "5")], marker: nil)]
        let service = Self.makeService(stub)

        // The balance refresh performs the one and only walk.
        _ = try await service.getTokenBalance(coin: Self.coin(tokenId: "USD.\(Self.issuer)"), address: Self.account)
        let callsAfterBalance = stub.callCount

        let held = await service.trustLineState(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account
        )
        let missing = await service.trustLineState(
            for: Self.coin(tokenId: "EUR.\(Self.issuer)"),
            address: Self.account
        )

        XCTAssertEqual(held, .present)
        XCTAssertEqual(missing, .absent)
        XCTAssertEqual(stub.callCount, callsAfterBalance, "the presence check must not issue its own request")
    }

    /// A currency spelled as a 3-char code in the coin id and as 40-char hex on
    /// the ledger (or vice versa) is the SAME line.
    func testTrustLinePresenceMatchesAcrossCurrencySpellings() async throws {
        let stub = RippleTrustLineStub()
        stub.pages = [Self.linesJSON([Self.line(currency: Self.rlusdHex, issuer: Self.issuer, balance: "1")], marker: nil)]
        let service = Self.makeService(stub)
        _ = try await service.fetchAccountLines(for: Self.account)

        let upper = await service.trustLineState(
            for: Self.coin(tokenId: "\(Self.rlusdHex).\(Self.issuer)"),
            address: Self.account
        )
        let lower = await service.trustLineState(
            for: Self.coin(tokenId: "\(Self.rlusdHex.lowercased()).\(Self.issuer)"),
            address: Self.account
        )

        XCTAssertEqual(upper, .present)
        XCTAssertEqual(lower, .present)
    }

    /// A DIFFERENT issuer's line for the same currency is not this token's line —
    /// XRPL keys a token by the (currency, issuer) pair.
    func testTrustLinePresenceIsIssuerSpecific() async throws {
        let stub = RippleTrustLineStub()
        stub.pages = [Self.linesJSON([Self.line(currency: "USD", issuer: Self.otherIssuer, balance: "1")], marker: nil)]
        let service = Self.makeService(stub)
        _ = try await service.fetchAccountLines(for: Self.account)

        let state = await service.trustLineState(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account
        )
        XCTAssertEqual(state, .absent)
    }

    /// A state never observed is `.unknown`, NOT `.absent`: offering to open a
    /// line we have no evidence is missing would invite a keysign ceremony (and a
    /// fee) for nothing.
    func testTrustLinePresenceIsUnknownBeforeAnyWalk() async {
        let service = Self.makeService(RippleTrustLineStub())

        let state = await service.trustLineState(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account
        )
        XCTAssertEqual(state, .unknown)
    }

    /// An unfunded account demonstrably holds no lines, which IS evidence — so
    /// its tokens correctly offer activation.
    func testUnfundedAccountReportsAbsentRatherThanUnknown() async throws {
        let stub = RippleTrustLineStub()
        stub.pages = [#"{"result":{"error":"actNotFound","status":"error"}}"#]
        let service = Self.makeService(stub)
        _ = try await service.fetchAccountLines(for: Self.account)

        let state = await service.trustLineState(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account
        )
        XCTAssertEqual(state, .absent)
    }

    // MARK: - Destination trust-line guard (#4758)

    func testDestinationWithAMatchingLineCanReceive() async {
        let stub = RippleTrustLineStub()
        stub.pages = [Self.linesJSON([Self.line(currency: "USD", issuer: Self.issuer, balance: "0")], marker: nil)]
        let service = Self.makeService(stub)

        let state = await service.destinationTrustLine(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            destination: "rDestination111111111111111111111"
        )
        XCTAssertEqual(state, .canReceive, "a zero-balance line still receives")
    }

    func testDestinationWithNoMatchingLineIsBlocked() async {
        let stub = RippleTrustLineStub()
        stub.pages = [Self.linesJSON([Self.line(currency: "EUR", issuer: Self.issuer, balance: "1")], marker: nil)]
        let service = Self.makeService(stub)

        let state = await service.destinationTrustLine(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            destination: "rDestination111111111111111111111"
        )
        XCTAssertEqual(state, .noTrustLine)
    }

    /// The ISSUER can always receive its own obligations back — no line needed on
    /// its side — so a send to the issuer must not be blocked.
    func testSendToTheIssuerItselfIsNeverBlocked() async {
        let stub = RippleTrustLineStub()
        let service = Self.makeService(stub)

        let state = await service.destinationTrustLine(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            destination: Self.issuer
        )
        XCTAssertEqual(state, .canReceive)
        XCTAssertEqual(stub.callCount, 0, "paying the issuer needs no lookup at all")
    }

    /// FAIL OPEN: a transport failure is not evidence the destination can't
    /// receive, and must never start blocking a send that worked before this
    /// guard existed.
    func testTransportFailureFailsOpen() async {
        let stub = RippleTrustLineStub()
        stub.pages = []  // exhausted → the stub throws
        let service = Self.makeService(stub)

        let state = await service.destinationTrustLine(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            destination: "rDestination111111111111111111111"
        )
        XCTAssertEqual(state, .unknown)
    }

    /// An uninterpretable HTTP-200 body is also not proof — fail open.
    func testMalformedResponseFailsOpen() async {
        let stub = RippleTrustLineStub()
        stub.pages = [#"{"result":{"status":"success"}}"#]  // no `lines`, no error
        let service = Self.makeService(stub)

        let state = await service.destinationTrustLine(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            destination: "rDestination111111111111111111111"
        )
        XCTAssertEqual(state, .unknown)
    }

    func testUnreadableTokenIdFailsOpen() async {
        let service = Self.makeService(RippleTrustLineStub())

        let state = await service.destinationTrustLine(
            for: Self.coin(tokenId: "not-a-token-id"),
            destination: "rDestination111111111111111111111"
        )
        XCTAssertEqual(state, .unknown)
    }

    // MARK: - Reserve quote (#4757)

    /// The owner-reserve cost comes from the LIVE `reserve_inc`, not from the
    /// mainnet seed: "0.2 XRP" is a current validator-vote value, not a constant.
    func testQuoteUsesTheLiveOwnerReserveIncrement() {
        // 0.5 XRP increment — deliberately NOT the 0.2 XRP mainnet seed.
        let quote = RippleTrustLineActivationQuote(
            ownerReserveDrops: BigInt(500_000),
            feeDrops: BigInt(20),
            spendableDrops: BigInt(5_000_000),
            limitValue: "1000000000000000",
            currencyCode: "USD",
            issuer: Self.issuer
        )

        XCTAssertEqual(quote.totalCostDrops, BigInt(500_020))
        XCTAssertEqual(quote.remainingSpendableDrops, BigInt(4_499_980))
        XCTAssertTrue(quote.isAffordable)
        XCTAssertNotEqual(
            quote.ownerReserveDrops,
            RippleReserve.seedReserveIncDrops,
            "the quote must reflect the live value, not the seed"
        )
    }

    /// Blocks when spendable XRP won't cover `reserve_inc + fee` — the TrustSet
    /// would otherwise fail on-ledger with the fee already burned.
    func testQuoteBlocksWhenSpendableXrpCannotCoverReservePlusFee() {
        let short = RippleTrustLineActivationQuote(
            ownerReserveDrops: BigInt(200_000),
            feeDrops: BigInt(20),
            spendableDrops: BigInt(200_019),
            limitValue: "1",
            currencyCode: "USD",
            issuer: Self.issuer
        )
        XCTAssertFalse(short.isAffordable)
        XCTAssertEqual(short.remainingSpendableDrops, .zero, "an unaffordable activation never shows a negative balance")

        // Exactly enough is enough.
        let exact = RippleTrustLineActivationQuote(
            ownerReserveDrops: BigInt(200_000),
            feeDrops: BigInt(20),
            spendableDrops: BigInt(200_020),
            limitValue: "1",
            currencyCode: "USD",
            issuer: Self.issuer
        )
        XCTAssertTrue(exact.isAffordable)
        XCTAssertEqual(exact.remainingSpendableDrops, .zero)
    }

    func testQuoteDecodesAHexCurrencyToItsTicker() {
        let quote = RippleTrustLineActivationQuote(
            ownerReserveDrops: BigInt(200_000),
            feeDrops: BigInt(10),
            spendableDrops: BigInt(10_000_000),
            limitValue: "1",
            currencyCode: Self.rlusdHex,
            issuer: Self.issuer
        )
        XCTAssertEqual(quote.currencyTicker, "RLUSD")
    }

    // MARK: - Verify / Join summary rows (#4757 step 16)

    /// A TrustSet gets issuer / currency / limit rows derived from the PAYLOAD, so
    /// a co-signer that holds nothing else still sees what it is signing rather
    /// than a blind signature.
    func testTrustSetPresentationDerivesRowsFromThePayload() throws {
        let payload = Self.makeTrustSetPayload(
            tokenId: "USD.\(Self.issuer)",
            toAmount: BigInt("1500000000000000")
        )

        let display = try XCTUnwrap(RippleTrustSetPresentation.display(for: payload))
        XCTAssertEqual(display.issuer, Self.issuer)
        XCTAssertEqual(display.currencyCode, "USD")
        XCTAssertEqual(display.ticker, "USD")
        XCTAssertEqual(display.limitValue, "1.5", "the amount is the trust-line LIMIT, shown as such")
    }

    func testTrustSetPresentationDecodesAHexCurrencyToItsTicker() throws {
        let payload = Self.makeTrustSetPayload(
            tokenId: "\(Self.rlusdHex).\(Self.issuer)",
            toAmount: RippleTrustLineLimit.defaultLimit
        )

        let display = try XCTUnwrap(RippleTrustSetPresentation.display(for: payload))
        XCTAssertEqual(display.ticker, "RLUSD")
        XCTAssertEqual(display.currencyCode, Self.rlusdHex)
        XCTAssertEqual(display.limitValue, "1000000000000000")
    }

    /// Not a TrustSet → no trust-line rows, so an ordinary send keeps the Payment
    /// framing it always had.
    func testTrustSetPresentationIsNilForEveryOtherTransaction() {
        let tokenPayment = Self.makeTrustSetPayload(
            tokenId: "USD.\(Self.issuer)",
            toAmount: BigInt(1),
            transactionType: .unspecified
        )
        XCTAssertNil(RippleTrustSetPresentation.display(for: tokenPayment))
        XCTAssertNil(RippleTrustSetPresentation.display(for: nil))
        XCTAssertFalse(RippleTrustSetPresentation.isTrustSet(payload: tokenPayment))
    }

    /// A token id the signer would refuse yields no rows rather than a guess —
    /// showing invented issuer/limit values for a transaction that cannot be
    /// built would be worse than showing nothing.
    func testTrustSetPresentationIsNilForAnUnreadableTokenId() {
        let payload = Self.makeTrustSetPayload(tokenId: "not-a-token-id", toAmount: BigInt(1))
        XCTAssertNil(RippleTrustSetPresentation.display(for: payload))
    }

    // MARK: - Fixtures

    private static func makeService(_ stub: RippleTrustLineStub) -> RippleService {
        RippleService(resolver: NoOverrideTrustLineResolver(), httpClient: stub, sleep: { _ in })
    }

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

    private static func makeTrustSetPayload(
        tokenId: String,
        toAmount: BigInt,
        transactionType: VSTransactionType = .rippleTrustSet
    ) -> KeysignPayload {
        let meta = coin(tokenId: tokenId)
        let coin = Coin(
            asset: meta,
            address: account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        return KeysignPayload(
            coin: coin,
            toAddress: issuer,
            toAmount: toAmount,
            chainSpecific: .Ripple(
                sequence: 1,
                gas: 10,
                lastLedgerSequence: 100,
                transactionType: transactionType.rawValue
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "iPhone-test",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
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
}

// MARK: - Test doubles

private final class NoOverrideTrustLineResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

/// Serves canned `account_lines` bodies in order and counts the calls, so a test
/// can assert that a surface adds NO request of its own.
private final class RippleTrustLineStub: HTTPClientProtocol, @unchecked Sendable {

    enum StubError: Error {
        case unexpectedMethod(String?)
        case exhausted
    }

    var pages: [String] = []

    private(set) var callCount = 0

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        guard Self.rpcMethod(of: target) == "account_lines" else {
            throw StubError.unexpectedMethod(Self.rpcMethod(of: target))
        }
        callCount += 1
        guard callCount <= pages.count else { throw StubError.exhausted }
        return HTTPResponse(data: Data(pages[callCount - 1].utf8), response: Self.ok)
    }

    private static func rpcMethod(of target: TargetType) -> String? {
        guard case let .requestCodable(body, _) = target.task,
              let data = try? JSONEncoder().encode(body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["method"] as? String
    }

    private static let ok = HTTPURLResponse(
        url: RippleAPI.defaultHost,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}
