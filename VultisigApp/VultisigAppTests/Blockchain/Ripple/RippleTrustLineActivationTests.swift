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

    /// A bare ticker longer than 3 characters is accepted and packed into the
    /// on-ledger hex form. Requiring the hex would have meant asking a user to
    /// type 40 characters to add SOLO — the flow would technically work and be
    /// unusable.
    ///
    /// The earlier worry that this forks a token into two coins does not hold:
    /// both spellings normalize through `toXrplCurrencyCode` BEFORE the token id
    /// is built, so they produce the same id. `testTickerAndHexSpellingsResolve
    /// ToTheSameToken` is the standing proof of that.
    func testUnnormalizedTickerIsAcceptedAndNormalized() throws {
        for ticker in ["RLUSD", "USDC", "SOLO", "USDT"] {
            XCTAssertTrue(
                RippleCustomTokenResolver.isValidInput("\(ticker).\(Self.issuer)"),
                "'\(ticker)' is how a user actually spells the token"
            )
            let normalized = try XCTUnwrap(
                RippleCustomTokenResolver.normalized(from: "\(ticker).\(Self.issuer)")
            )
            XCTAssertEqual(normalized.currency, try RippleIssuedCurrency.toXrplCurrencyCode(ticker))
            XCTAssertEqual(normalized.currency.count, 40, "a >3-char ticker must reach the ledger as hex")
        }
    }

    /// The two spellings of one token must resolve to one coin. `CoinMeta`
    /// identity is `chain-ticker-contractAddress`, so a divergence here would
    /// put the same trust line in the asset list twice.
    func testTickerAndHexSpellingsResolveToTheSameToken() throws {
        let fromTicker = try RippleCustomTokenResolver.resolve(input: "RLUSD.\(Self.issuer)")
        let fromHex = try RippleCustomTokenResolver.resolve(input: "\(Self.rlusdHex).\(Self.issuer)")

        XCTAssertEqual(fromTicker.contractAddress, fromHex.contractAddress)
        XCTAssertEqual(fromTicker.uniqueId, fromHex.uniqueId)
    }

    /// A 3-character ticker must NOT be packed to hex: the ledger carries it as
    /// a standard code, and the ASCII-packed hex of a 3-character code is a
    /// different currency. This is the asymmetry that makes the widened rule
    /// safe rather than a blanket "pack everything".
    func testThreeCharacterTickerIsStillTreatedAsAStandardCode() throws {
        let normalized = try XCTUnwrap(RippleCustomTokenResolver.normalized(from: "USD.\(Self.issuer)"))

        XCTAssertEqual(normalized.currency, "USD")
    }

    /// `asciiToHexCurrencyCode` will encode whatever UTF-8 bytes it is handed,
    /// so the validator — not the encoder — has to refuse non-ASCII. Otherwise a
    /// pasted lookalike packs into a well-formed code for a token nobody meant.
    func testNonAsciiTickerIsRejected() {
        for ticker in ["SÖLO", "SOL⍺", "🪙"] {
            XCTAssertFalse(
                RippleCustomTokenResolver.isValidInput("\(ticker).\(Self.issuer)"),
                "'\(ticker)' is not a code the ledger can carry"
            )
        }
    }

    /// A 3-UTF16-unit string is not automatically a standard currency code.
    /// Outside the ledger's ASCII repertoire it is 4+ UTF-8 bytes, and a standard
    /// code is encoded by copying exactly 3 bytes into positions 12–14 of the
    /// 160-bit field — so such a code matches neither that form nor the
    /// 40-character hex one, and the token would be addable but unsignable.
    func testNonAsciiThreeUnitCurrencyCodeIsRejected() {
        for currency in ["\u{00C1}BC", "\u{20AC}UR", "US\u{00A9}", "A\u{1F600}"] {
            XCTAssertEqual(
                currency.utf16.count, 3,
                "'\(currency)' must reach the standard-code branch for this test to mean anything"
            )
            XCTAssertFalse(
                RippleCustomTokenResolver.isValidInput("\(currency).\(Self.issuer)"),
                "'\(currency)' is not a code the ledger can carry"
            )
            XCTAssertNil(
                RippleCustomTokenResolver.normalized(from: "\(currency).\(Self.issuer)"),
                "'\(currency)' must not fall through to the packable-ticker branch"
            )
        }
    }

    /// The repertoire the ledger itself checks a standard code against, taken
    /// verbatim from rippled's `kIsoCharSet`. Pinned so nobody narrows it to
    /// "alphanumeric" and starts rejecting currencies the XRP Ledger accepts.
    func testTheLedgersStandardCodeSymbolsAreAccepted() {
        for symbol in "<>(){}[]|?!@#$%^&*" {
            XCTAssertTrue(
                RippleCustomTokenResolver.isValidInput("A\(symbol)1.\(Self.issuer)"),
                "'\(symbol)' is in the ledger's standard-code repertoire"
            )
        }
    }

    /// Anything outside that repertoire is rejected — and, crucially, is not
    /// re-read as a packable ticker. All of these are 3 bytes of printable ASCII,
    /// so without the terminal standard-code branch they would pack into the hex
    /// form and resolve to a different on-ledger currency than the one typed.
    func testCharactersOutsideTheStandardRepertoireAreRejected() {
        for currency in ["A-B", "A+B", "A/B", "A_B", "A B", "A,B", "A;B", "A~B", "A'B", "A=B"] {
            XCTAssertFalse(
                RippleCustomTokenResolver.isValidInput("\(currency).\(Self.issuer)"),
                "'\(currency)' is not a standard code the ledger accepts"
            )
            XCTAssertNil(
                RippleCustomTokenResolver.normalized(from: "\(currency).\(Self.issuer)"),
                "'\(currency)' must not fall through to the packable-ticker branch"
            )
        }
    }

    /// Lowercase letters are in the ledger's repertoire but not in this app's.
    /// XRPL currency codes are case-SENSITIVE, while WalletCore uppercases a
    /// 3-character code before encoding it — so `usd` would sign as `USD`, a
    /// different currency from the one added, displayed and matched against
    /// `account_lines`. Refusing the spelling beats signing a token the user did
    /// not choose.
    func testLowercaseStandardCurrencyCodeIsRejected() {
        for currency in ["usd", "uSd", "abc"] {
            XCTAssertFalse(
                RippleCustomTokenResolver.isValidInput("\(currency).\(Self.issuer)"),
                "'\(currency)' would not survive the signer's uppercasing"
            )
            XCTAssertNil(RippleCustomTokenResolver.normalized(from: "\(currency).\(Self.issuer)"))
        }
    }

    /// The escape hatch that keeps the lowercase exclusion from removing a
    /// currency outright: its hex spelling is accepted and normalized verbatim,
    /// and that is the form the signer encodes byte for byte.
    func testLowercaseCodeStaysReachableThroughItsHexSpelling() throws {
        // A standard code occupies bytes 12–14 of the 160-bit field: 24 hex zeros,
        // then `usd` as ASCII, then 10 more.
        let hex = String(repeating: "0", count: 24) + "757364" + String(repeating: "0", count: 10)
        XCTAssertEqual(hex.count, 40)

        let normalized = try XCTUnwrap(RippleCustomTokenResolver.normalized(from: "\(hex).\(Self.issuer)"))

        XCTAssertEqual(normalized.currency, hex)
    }

    /// 20 bytes is the 160-bit ceiling; 21 cannot be represented.
    func testTickerLongerThanTwentyBytesIsRejected() {
        XCTAssertTrue(
            RippleCustomTokenResolver.isValidInput("\(String(repeating: "A", count: 20)).\(Self.issuer)")
        )
        XCTAssertFalse(
            RippleCustomTokenResolver.isValidInput("\(String(repeating: "A", count: 21)).\(Self.issuer)")
        )
    }

    /// `XRP` is reserved for the native asset and can never name an issued
    /// currency, so it must not resolve to a token.
    func testNativeXrpCurrencyCodeIsRejected() {
        XCTAssertFalse(RippleCustomTokenResolver.isValidInput("XRP.\(Self.issuer)"))
        XCTAssertFalse(RippleCustomTokenResolver.isValidInput("xrp.\(Self.issuer)"))
    }

    /// Padding `XRP` must not smuggle it past the reservation. The currency
    /// half is trimmed before validation precisely so the gate cannot see a
    /// 4-byte ticker where the encoder will see the reserved 3-byte code:
    /// `parseRippleTokenId` splits without trimming, `toXrplCurrencyCode`
    /// trims, and the gap between them is the hole.
    func testWhitespacePaddedNativeXrpCodeIsRejected() {
        for input in ["XRP .\(Self.issuer)", " XRP.\(Self.issuer)", "xrp\t.\(Self.issuer)"] {
            XCTAssertFalse(
                RippleCustomTokenResolver.isValidInput(input),
                "'\(input)' normalizes to the reserved native code"
            )
        }
    }

    /// Whatever the gate accepted must be what the encoder encodes. A padded
    /// ticker resolves to the same coin as the clean spelling rather than to a
    /// second, space-padded currency.
    func testWhitespacePaddedTickerResolvesToTheSameTokenAsTheCleanSpelling() throws {
        let padded = try RippleCustomTokenResolver.resolve(input: "RLUSD .\(Self.issuer)")
        let clean = try RippleCustomTokenResolver.resolve(input: "RLUSD.\(Self.issuer)")

        XCTAssertEqual(padded.uniqueId, clean.uniqueId)
        XCTAssertEqual(padded.contractAddress, "\(Self.rlusdHex).\(Self.issuer)")
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
            // 39 characters — one short of the 160-bit hex form, and far past
            // the 20 bytes a ticker can be packed into.
            "\(String(repeating: "A", count: 39)).\(Self.issuer)",
            // 40 characters but not hex, so it is neither form.
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
        for input in [
            // No separator at all.
            "not-a-token-id",
            // Reserved for the native asset.
            "XRP.\(Self.issuer)",
            // 21 bytes — one past the 160-bit ceiling, so unpackable.
            "\(String(repeating: "A", count: 21)).\(Self.issuer)",
            // Well-formed currency, but the issuer is not an XRPL address.
            "RLUSD.not-an-address"
        ] {
            XCTAssertThrowsError(
                try RippleCustomTokenResolver.resolve(input: input),
                "'\(input)' should not resolve"
            )
        }
    }

    /// A trust line costs an owner reserve on the XRP account that holds it, so
    /// the flow must require the vault to have XRP enabled.
    func testResolverRequiresTheVaultNativeCoin() {
        XCTAssertTrue(RippleCustomTokenResolver.requiresVaultNativeCoin)
    }

    /// The curated `EQ` entry has to win on the custom-token path too, not only in
    /// discovery. Equilibrium's on-ledger code decodes to the long name, so without
    /// the curated hit a hand-added coin would be tickered `Equilibrium` — a
    /// different `uniqueId` from the discovered row, and therefore the same trust
    /// line listed twice.
    func testCuratedEquilibriumEntryWinsOnTheCustomTokenPath() throws {
        let curated = try XCTUnwrap(TokensStore.TokenSelectionAssets.first {
            $0.chain == .ripple && $0.ticker == "EQ"
        })

        let resolved = try RippleCustomTokenResolver.resolve(input: curated.contractAddress)

        XCTAssertEqual(resolved.ticker, "EQ")
        XCTAssertEqual(resolved.uniqueId, curated.uniqueId)
        XCTAssertEqual(resolved.priceProviderId, "equilibrium")
    }

    /// Typing the name rather than the 40-char code must land on the same curated
    /// coin — the widened gate and the curated catalog have to agree, or the two
    /// ways of adding one token produce two coins.
    func testCuratedEntryIsReachedByTypingTheTickerRatherThanTheHex() throws {
        let curated = try XCTUnwrap(TokensStore.TokenSelectionAssets.first {
            $0.chain == .ripple && $0.ticker == "SOLO"
        })
        let (_, issuer) = try RippleIssuedCurrency.parseRippleTokenId(curated.contractAddress)

        let resolved = try RippleCustomTokenResolver.resolve(input: "SOLO.\(issuer)")

        XCTAssertEqual(resolved.uniqueId, curated.uniqueId)
        XCTAssertEqual(resolved.priceProviderId, "solo-coin")
    }

    /// The factory must route `.ripple` to the XRPL strategy rather than letting it
    /// fall through to the EVM-like metadata lookup, which would try three
    /// `eth_call`s against an XRPL token id.
    func testFactoryRoutesRippleToTheXrplResolver() {
        let resolver = CustomTokenResolverFactory.make(chain: .ripple)

        XCTAssertTrue(resolver.validate("USD.\(Self.issuer)"))
        XCTAssertFalse(resolver.validate("0x0000000000000000000000000000000000000000"))
        XCTAssertTrue(resolver.requiresVaultNativeCoin)
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

    /// A recording that has gone stale degrades to `.unknown`, not `.absent`.
    /// Without this an `Activate` button would sit there forever on evidence that
    /// is no longer true — a line opened on another device, or a walk that has
    /// been failing for a while — inviting a redundant ceremony and its fee.
    func testStaleTrustLineSnapshotDegradesToUnknown() async {
        let service = Self.makeService(RippleTrustLineStub())
        let key = RippleService.trustLinesCacheKey(for: RippleAPI.defaultHost, address: Self.account)

        // Seed a snapshot recorded an hour ago, well past the presence TTL.
        await service.trustLinesCache.setCached(
            RippleTrustLineSnapshot(lines: [], recordedAt: Date(timeIntervalSinceNow: -3_600)),
            for: key
        )

        let stale = await service.trustLineState(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account
        )
        XCTAssertEqual(stale, .unknown)

        // A fresh recording of the same (empty) result IS evidence.
        await service.trustLinesCache.setCached(
            RippleTrustLineSnapshot(lines: [], recordedAt: Date()),
            for: key
        )
        let fresh = await service.trustLineState(
            for: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account
        )
        XCTAssertEqual(fresh, .absent)
    }

    /// The batch accessor resolves the host ONCE, so one answer set can never be
    /// assembled from two networks' snapshots, and answers every coin it is given.
    func testBatchPresenceAnswersEveryCoinFromOneSnapshot() async throws {
        let stub = RippleTrustLineStub()
        stub.pages = [Self.linesJSON([Self.line(currency: "USD", issuer: Self.issuer, balance: "5")], marker: nil)]
        let service = Self.makeService(stub)
        _ = try await service.fetchAccountLines(for: Self.account)

        let held = Self.coin(tokenId: "USD.\(Self.issuer)")
        let missing = Self.coin(tokenId: "EUR.\(Self.issuer)")
        let unreadable = Self.coin(tokenId: "not-a-token-id")

        let states = await service.trustLineStates(for: [held, missing, unreadable], address: Self.account)

        XCTAssertEqual(states[held.contractAddress], .present)
        XCTAssertEqual(states[missing.contractAddress], .absent)
        XCTAssertEqual(states[unreadable.contractAddress], .unknown)
        XCTAssertEqual(stub.callCount, 1, "the batch read must not issue its own request")
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

    /// The limit the sheet DISPLAYS and the limit that gets SIGNED must be the
    /// same number. The displayed value is a decimal string that travels through
    /// `Decimal` in `SendCryptoLogic.amountInRaw` before becoming the keysign
    /// amount, so a precision loss there would sign a different limit than the one
    /// the user approved.
    @MainActor
    func testActivationTransactionSignsExactlyTheDisplayedLimit() async {
        let viewModel = RippleTrustLineActivationViewModel(service: Self.makeService(RippleTrustLineStub()))
        let meta = Self.coin(tokenId: "USD.\(Self.issuer)")
        let coin = Coin(
            asset: meta,
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        let vault = Vault.example
        let nativeCoin = Coin(
            asset: CoinMeta(
                chain: .ripple,
                ticker: "XRP",
                logo: "xrp",
                decimals: 6,
                priceProviderId: "ripple",
                contractAddress: "",
                isNativeToken: true
            ),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        nativeCoin.rawBalance = "50000000"

        await viewModel.load(coin: coin, nativeCoin: nativeCoin)

        let tx = viewModel.makeActivationTransaction(coin: coin, vault: vault)
        let transaction = try? XCTUnwrap(tx)
        guard let transaction else { return XCTFail("expected an activation transaction") }

        XCTAssertEqual(transaction.transactionType, .rippleTrustSet)
        XCTAssertEqual(transaction.amount, RippleTrustLineLimit.defaultLimitDisplayValue())
        XCTAssertEqual(
            transaction.amountInRaw,
            RippleTrustLineLimit.defaultLimit,
            "the signed limit must equal the displayed limit exactly"
        )
        // And that raw amount formats back to the same string the sheet showed.
        XCTAssertEqual(
            try? RippleIssuedCurrency.formatIssuedCurrencyValue(
                amount: transaction.amountInRaw,
                decimals: coin.decimals
            ),
            viewModel.quote?.limitValue
        )
    }

    /// Two taps in one runloop turn must not both start a quote. If they do, the
    /// two `load`s interleave over one `quote` and the sheet can pair one token
    /// with another token's reserve, limit and issuer.
    @MainActor
    func testOnlyOneActivationCanBeInFlightAtATime() {
        let viewModel = RippleTrustLineActivationViewModel(service: Self.makeService(RippleTrustLineStub()))

        XCTAssertTrue(viewModel.beginLoading(), "the first tap claims the slot")
        XCTAssertFalse(viewModel.beginLoading(), "a second tap in the same turn must be refused")
        XCTAssertFalse(viewModel.beginLoading())
    }

    /// The slot has to be released once the quote resolves, or Activate is dead
    /// for the rest of the session.
    @MainActor
    func testTheActivationSlotIsReleasedAfterLoading() async {
        let viewModel = RippleTrustLineActivationViewModel(service: Self.makeService(RippleTrustLineStub()))
        let coin = Coin(
            asset: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        let nativeCoin = Coin(
            asset: CoinMeta(
                chain: .ripple,
                ticker: "XRP",
                logo: "xrp",
                decimals: 6,
                priceProviderId: "ripple",
                contractAddress: "",
                isNativeToken: true
            ),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        nativeCoin.rawBalance = "50000000"

        XCTAssertTrue(viewModel.beginLoading())
        await viewModel.load(coin: coin, nativeCoin: nativeCoin)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.beginLoading(), "a later tap must be able to quote again")
    }

    /// The sheet shows the limit grouped, because 16 unseparated digits are not a
    /// number a user can check — and this row exists to be checked before signing.
    /// The grouped string must still be the exact figure that gets signed.
    @MainActor
    func testLimitDisplayGroupsTheSignedValueWithoutChangingIt() async {
        let viewModel = RippleTrustLineActivationViewModel(service: Self.makeService(RippleTrustLineStub()))
        let coin = Coin(
            asset: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        let nativeCoin = Coin(
            asset: CoinMeta(
                chain: .ripple,
                ticker: "XRP",
                logo: "xrp",
                decimals: 6,
                priceProviderId: "ripple",
                contractAddress: "",
                isNativeToken: true
            ),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        nativeCoin.rawBalance = "50000000"

        await viewModel.load(coin: coin, nativeCoin: nativeCoin)

        let display = viewModel.limitDisplay
        XCTAssertNotNil(display)
        XCTAssertNotEqual(display, viewModel.quote?.limitValue, "the raw 16-digit run must be grouped")
        // Stripping the grouping separators recovers the exact signed value, so
        // formatting cannot have rounded or abbreviated it.
        let separator = Locale.current.groupingSeparator ?? ","
        XCTAssertEqual(
            display?.replacingOccurrences(of: separator, with: ""),
            viewModel.quote?.limitValue
        )
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

    // MARK: - Done-screen hero

    /// The done screen renders `toAmountWithTickerString` unless a hero claims the
    /// slot. A TrustSet's `toAmount` is the trust-line LIMIT, so without a hero the
    /// receipt announces a 1,000,000,000,000,000-token payment that never happened
    /// — and prices it in fiat. Observed on mainnet before this existed.
    func testTrustSetSuppliesADoneHeroSoTheLimitIsNotShownAsATransfer() throws {
        let payload = Self.makeTrustSetPayload(
            tokenId: "\(Self.rlusdHex).\(Self.issuer)",
            toAmount: RippleTrustLineLimit.defaultLimit
        )

        let hero = try XCTUnwrap(RippleTrustSetPresentation.hero(for: payload))

        guard case .title(let text, let caption) = hero else {
            return XCTFail("a TrustSet receipt must not use an amount hero")
        }
        XCTAssertTrue(text.contains("RLUSD"), "the hero names the token whose line was opened")
        XCTAssertEqual(caption, Self.issuer, "the issuer identifies WHICH line was opened")
        XCTAssertFalse(
            text.contains("1000000000000000"),
            "the limit must not be presented as an amount transferred"
        )
    }

    /// An ordinary token Payment keeps the default amount hero — the fix must not
    /// swallow the amount on transactions that genuinely have one.
    func testNonTrustSetGetsNoDoneHeroOverride() {
        let tokenPayment = Self.makeTrustSetPayload(
            tokenId: "\(Self.rlusdHex).\(Self.issuer)",
            toAmount: BigInt("1048869990000000"),
            transactionType: .unspecified
        )

        XCTAssertNil(RippleTrustSetPresentation.hero(for: tokenPayment))
        XCTAssertNil(RippleTrustSetPresentation.hero(for: nil))
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

    /// THE state distinction that keeps a co-signer safe: whether something IS a
    /// TrustSet is decided by the discriminator, never by whether we managed to
    /// render it. An unreadable TrustSet must resolve to `.unreviewable` — if it
    /// collapsed to "not a TrustSet", the summary would fall back to the Payment
    /// rows and present `toAddress` as a recipient and the LIMIT as a transfer,
    /// asking a peer device to join after reviewing a materially false operation.
    func testUnreadableTrustSetIsUnreviewableRatherThanNotATrustSet() {
        for tokenId in ["not-a-token-id", "", "USD.", ".rIssuer"] {
            let payload = Self.makeTrustSetPayload(tokenId: tokenId, toAmount: BigInt(1))

            XCTAssertTrue(
                RippleTrustSetPresentation.isTrustSet(payload: payload),
                "'\(tokenId)': the discriminator alone decides the operation"
            )
            XCTAssertEqual(
                RippleTrustSetPresentation.state(for: payload),
                .unreviewable,
                "'\(tokenId)' must never fall back to Payment framing"
            )
        }
    }

    /// Hostile `decimals` make the limit unformattable — also `.unreviewable`,
    /// not a silent fallback to Payment rows.
    func testTrustSetWithHostileDecimalsIsUnreviewable() {
        let meta = CoinMeta(
            chain: .ripple,
            ticker: "USD",
            logo: .empty,
            decimals: -1,
            priceProviderId: .empty,
            contractAddress: "USD.\(Self.issuer)",
            isNativeToken: false
        )
        let coin = Coin(
            asset: meta,
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        let payload = KeysignPayload(
            coin: coin,
            toAddress: Self.issuer,
            toAmount: BigInt(1),
            chainSpecific: .Ripple(
                sequence: 1,
                gas: 10,
                lastLedgerSequence: 100,
                transactionType: VSTransactionType.rippleTrustSet.rawValue
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

        XCTAssertEqual(RippleTrustSetPresentation.state(for: payload), .unreviewable)
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload),
            "an unreviewable TrustSet must also be unsignable"
        )
    }

    /// A readable TrustSet resolves to `.reviewable`, and an ordinary send to
    /// `.notTrustSet` — so nothing else changes shape.
    func testTrustSetStateDistinguishesReviewableFromNotATrustSet() throws {
        let readable = Self.makeTrustSetPayload(
            tokenId: "USD.\(Self.issuer)",
            toAmount: BigInt("1500000000000000")
        )
        guard case .reviewable(let display) = RippleTrustSetPresentation.state(for: readable) else {
            return XCTFail("expected a reviewable TrustSet")
        }
        XCTAssertEqual(display.limitValue, "1.5")

        let payment = Self.makeTrustSetPayload(
            tokenId: "USD.\(Self.issuer)",
            toAmount: BigInt(1),
            transactionType: .unspecified
        )
        XCTAssertEqual(RippleTrustSetPresentation.state(for: payment), .notTrustSet)
        XCTAssertEqual(RippleTrustSetPresentation.state(for: nil), .notTrustSet)
    }

    /// `fetchReserveValues` collapses every recoverable failure into a seeded
    /// `nil` and rethrows exactly one error: cancellation, which means this sheet
    /// is being torn down or superseded. Publishing a seeded quote then would
    /// price a token nobody is looking at — and the slot must still be released.
    @MainActor
    func testCancelledQuoteIsNotPublishedFromSeeds() async {
        let viewModel = RippleTrustLineActivationViewModel(
            service: Self.makeService(client: CancellingStub())
        )
        let coin = Coin(
            asset: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        let nativeCoin = Coin(
            asset: CoinMeta(
                chain: .ripple,
                ticker: "XRP",
                logo: "xrp",
                decimals: 6,
                priceProviderId: "ripple",
                contractAddress: "",
                isNativeToken: true
            ),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        nativeCoin.rawBalance = "50000000"

        await viewModel.load(coin: coin, nativeCoin: nativeCoin)

        XCTAssertNil(viewModel.quote, "a cancelled load must not publish a seeded quote")
        XCTAssertNil(viewModel.errorMessage, "cancellation is not an error to show")
        XCTAssertFalse(viewModel.isLoading, "the activation slot must still be released")
    }

    /// The view model is a screen-level `@StateObject`, so it outlives one sheet
    /// presentation. A load that returns before quoting must not leave the
    /// PREVIOUS token's reserve, limit and issuer standing for the new one —
    /// that is the exact mispairing `beginLoading` exists to prevent, arrived at
    /// from the other direction.
    @MainActor
    func testAFailedQuoteDoesNotLeaveThePreviousTokensQuoteStanding() async {
        let viewModel = RippleTrustLineActivationViewModel(service: Self.makeService(RippleTrustLineStub()))
        let nativeCoin = Coin(
            asset: CoinMeta(
                chain: .ripple,
                ticker: "XRP",
                logo: "xrp",
                decimals: 6,
                priceProviderId: "ripple",
                contractAddress: "",
                isNativeToken: true
            ),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        nativeCoin.rawBalance = "50000000"

        let first = Coin(
            asset: Self.coin(tokenId: "USD.\(Self.issuer)"),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        await viewModel.load(coin: first, nativeCoin: nativeCoin)
        XCTAssertNotNil(viewModel.quote, "the first token must quote for this test to mean anything")

        // A token id the resolver cannot read — `load` reports it and returns
        // before assigning a quote.
        let second = Coin(
            asset: Self.coin(tokenId: "no-separator"),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        await viewModel.load(coin: second, nativeCoin: nativeCoin)

        XCTAssertNil(viewModel.quote, "the previous token's quote must not survive into a failed load")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Fixtures

    private static func makeService(_ stub: RippleTrustLineStub) -> RippleService {
        RippleService(resolver: NoOverrideTrustLineResolver(), httpClient: stub, sleep: { _ in })
    }

    private static func makeService(client: HTTPClientProtocol) -> RippleService {
        RippleService(resolver: NoOverrideTrustLineResolver(), httpClient: client, sleep: { _ in })
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

/// Answers every RPC with `CancellationError`, modelling a sheet torn down
/// mid-load.
private struct CancellingStub: HTTPClientProtocol {
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        throw CancellationError()
    }
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
