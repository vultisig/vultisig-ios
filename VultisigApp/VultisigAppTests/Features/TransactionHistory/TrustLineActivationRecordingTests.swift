//
//  TrustLineActivationRecordingTests.swift
//  VultisigAppTests
//
//  Pins how an XRPL trust-line activation reaches transaction history, and what
//  the row it produces contains.
//
//  Regression: `TransactionHistoryRecording.record()` had no TrustSet branch, so
//  an activation fell through to `recordSend` carrying the transaction's amount
//  — which for a TrustSet is the trust-line LIMIT. Activating USDC recorded as a
//  send of 1,000,000,000,000,000 USDC, contradicting the verify summary and the
//  done screen, both of which already special-case the same value.
//
//  Two seams, tested separately because they fail in different ways:
//    - ROUTING (`isTrustLineActivation`) — a payload that isn't recognised falls
//      back to the send row.
//    - CONTENT (`trustLineActivationRow`) — a recognised payload whose row still
//      carries the limit somewhere would be the same lie in a new type.
//

@testable import VultisigApp
import BigInt
import VultisigCommonData
import XCTest

@MainActor
final class TrustLineActivationRecordingTests: XCTestCase {

    private static let account = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
    private static let issuer = "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"
    /// 160-bit hex form of `RLUSD` — the on-ledger code for a >3-character ticker.
    private static let rlusdHex = "524C555344000000000000000000000000000000"
    /// The limit `RippleTrustLineLimit.defaultLimit` signs, as it renders.
    private static let limitDisplayValue = "1000000000000000"

    // MARK: - Routing

    /// ⚠️ The assertion that actually holds the fix up. The predicate being true
    /// is not enough — the bug was never a missing predicate, it was a dispatch
    /// that asked the wrong question first. `route(for:)` answers the whole
    /// precedence chain, so deleting the activation branch or demoting it below
    /// the send fallback turns this red.
    ///
    /// The INITIATOR's shape: `SendDoneScreen` builds `amountCrypto` from the
    /// `SendTransaction`, so the string it hands over already reads as a
    /// quadrillion-token send.
    func testAnInitiatorsTrustSetIsRoutedToTheActivationRecorder() {
        let payload = makeDonePayload(
            amountCrypto: "\(Self.limitDisplayValue) RLUSD",
            keysignPayload: makeTrustSetPayload()
        )

        XCTAssertEqual(TransactionHistoryRecording.route(for: payload), .trustLineActivation)
        XCTAssertTrue(TransactionHistoryRecording.isTrustLineActivation(payload))
    }

    /// The CO-SIGNER's shape: `JoinKeysignDoneView.sendBranch` builds
    /// `amountCrypto` from the payload's `toAmount` instead. Different string,
    /// same lie — and a bug that only bites the non-initiating device is worse,
    /// not better.
    func testACosignersTrustSetIsRoutedToTheActivationRecorder() {
        let payload = makeDonePayload(
            amountCrypto: "\(Self.limitDisplayValue) RLUSD",
            keysignPayload: makeTrustSetPayload(),
            fromAddress: Self.account
        )

        XCTAssertEqual(TransactionHistoryRecording.route(for: payload), .trustLineActivation)
    }

    /// Why ONE branch fixes both devices: a TrustSet carries no swap payload and
    /// no limit-swap memo, so it never reaches `recordFromKeysignPayload` — both
    /// the initiator and the co-signer share the `recordSend` fallback at the
    /// bottom of the chain, and the activation branch sits above it.
    func testATrustSetIsInterceptedBeforeTheKeysignRecorderDispatch() {
        let keysignPayload = makeTrustSetPayload()
        let payload = makeDonePayload(amountCrypto: "0 RLUSD", keysignPayload: keysignPayload)

        XCTAssertEqual(TransactionHistoryRecording.route(for: payload), .trustLineActivation)
        XCTAssertFalse(
            TransactionHistoryRecording.routesThroughKeysignRecorder(keysignPayload),
            "a TrustSet has no swap payload and no limit memo — it shares the recordSend fallback"
        )
    }

    /// The new branch must not have displaced anything that was already routed.
    /// Each of these is a precedence the chain had before the activation case
    /// was inserted, re-asserted from above and below it.
    func testTheActivationBranchDoesNotDisplaceTheExistingRoutes() {
        // Above it: a payload with nothing to record still records nothing.
        XCTAssertEqual(
            TransactionHistoryRecording.route(
                for: makeDonePayload(amountCrypto: "1 XRP", keysignPayload: nil, hash: "")
            ),
            .skip,
            "an un-broadcast payload has no row to write"
        )
        XCTAssertEqual(
            TransactionHistoryRecording.route(
                for: makeDonePayload(amountCrypto: "1 XRP", keysignPayload: nil, pubKeyECDSA: "")
            ),
            .skip,
            "a preview payload carries no vault"
        )
        // Still above it: a limit-order cancel is suppressed even though the
        // order's own row keeps its hash reachable.
        XCTAssertEqual(
            TransactionHistoryRecording.route(
                for: makeDonePayload(
                    amountCrypto: "0 RUNE",
                    keysignPayload: nil,
                    memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0"
                )
            ),
            .skip
        )
        // Below it: the co-signer's swap dispatch and the plain send fallback.
        XCTAssertEqual(
            TransactionHistoryRecording.route(
                for: makeDonePayload(
                    amountCrypto: "1 RUNE",
                    keysignPayload: makeThorchainPayload(memo: "=<:BTC.BTC:bc1qexample:1e6:va:50")
                )
            ),
            .keysignPayload
        )
        XCTAssertEqual(
            TransactionHistoryRecording.route(
                for: makeDonePayload(amountCrypto: "1 RUNE", keysignPayload: makeThorchainPayload())
            ),
            .send
        )
        XCTAssertEqual(
            TransactionHistoryRecording.route(
                for: makeDonePayload(amountCrypto: "1 XRP", keysignPayload: nil, verb: .claim)
            ),
            .skip,
            "QBTC claims have no tx-history schema"
        )
    }

    /// ⚠️ The exact regression, stated as a route: an XRPL TrustSet must never
    /// come back `.send`. That is the single assertion that would have caught
    /// the shipped bug.
    func testATrustSetIsNeverRoutedToTheSendRow() {
        for tokenId in ["\(Self.rlusdHex).\(Self.issuer)", "USD.\(Self.issuer)", "not-a-token-id"] {
            let route = TransactionHistoryRecording.route(
                for: makeDonePayload(
                    amountCrypto: "\(Self.limitDisplayValue) RLUSD",
                    keysignPayload: makeTrustSetPayload(tokenId: tokenId)
                )
            )
            XCTAssertNotEqual(route, .send, "'\(tokenId)' would persist the trust-line limit as a transfer")
            XCTAssertEqual(route, .trustLineActivation, "'\(tokenId)'")
        }
    }

    /// ⚠️ Decided by the WIRE discriminator, never by whether the terms could be
    /// rendered. An unreadable token id must still record as an activation: if
    /// it collapsed to "not a TrustSet" it would fall back into the send row,
    /// which is the exact false record this closes.
    func testAnUnreadableTrustSetIsStillAnActivation() {
        for tokenId in ["not-a-token-id", "", "USD.", ".rIssuer"] {
            let payload = makeDonePayload(
                amountCrypto: "\(Self.limitDisplayValue) TEST",
                keysignPayload: makeTrustSetPayload(tokenId: tokenId)
            )
            XCTAssertTrue(
                TransactionHistoryRecording.isTrustLineActivation(payload),
                "'\(tokenId)': the discriminator alone decides the operation"
            )
        }
    }

    /// An ordinary XRPL token Payment genuinely moves tokens and keeps its send
    /// row — the fix must not swallow transactions that DO have an amount.
    func testATokenPaymentIsNotAnActivation() {
        let payload = makeDonePayload(
            amountCrypto: "12.5 RLUSD",
            keysignPayload: makeTrustSetPayload(transactionType: .unspecified)
        )

        XCTAssertFalse(TransactionHistoryRecording.isTrustLineActivation(payload))
        XCTAssertEqual(TransactionHistoryRecording.route(for: payload), .send)
    }

    /// Nothing on another chain, and nothing without a payload at all, can be
    /// mistaken for a trust-line activation.
    func testNonRipplePayloadsAreNotActivations() {
        XCTAssertFalse(
            TransactionHistoryRecording.isTrustLineActivation(
                makeDonePayload(amountCrypto: "1 BTC", keysignPayload: nil)
            ),
            "a payload with no keysign payload carries no discriminator"
        )
        XCTAssertFalse(
            TransactionHistoryRecording.isTrustLineActivation(
                makeDonePayload(amountCrypto: "1 RUNE", keysignPayload: makeThorchainPayload())
            ),
            "a THORChain payload has no XRPL operation to discriminate"
        )
    }

    // MARK: - Row content

    /// The row a recognised activation persists. Asserted field by field rather
    /// than as a whole, so a regression names which field went wrong.
    func testTheActivationRowCarriesNoAmountAndKeepsTheFeeAndExplorerLink() throws {
        let row = makeRow()

        XCTAssertEqual(row.type, .trustLineActivation)
        XCTAssertEqual(row.txHash, "TRUSTSETHASH")
        XCTAssertEqual(row.pubKeyECDSA, "pubkey-ecdsa")
        XCTAssertEqual(row.status, .inProgress)
        XCTAssertEqual(row.chainRawValue, Chain.ripple.rawValue)

        // The whole point: no amount, and no fiat price for one.
        XCTAssertTrue(row.amountCrypto.isEmpty, "a TrustSet transferred nothing")
        XCTAssertTrue(row.amountFiat.isEmpty, "and so it has no fiat value")
        XCTAssertNil(row.toAmountCrypto)
        XCTAssertNil(row.toAmountFiat)

        // The fee the user really paid, and the transaction itself, stay
        // reachable — that is why this row is recorded rather than suppressed.
        XCTAssertEqual(row.feeCrypto, "0.000012 XRP")
        XCTAssertEqual(row.feeFiat, "$0.00003")
        XCTAssertEqual(row.explorerLink, "https://xrpscan.com/tx/TRUSTSETHASH")

        // Who the line is with, and which currency it trusts.
        XCTAssertEqual(row.coinTicker, "RLUSD", "the resolved ticker, not the hex currency code")
        XCTAssertEqual(row.toAddress, Self.issuer)
        XCTAssertEqual(row.fromAddress, Self.account)

        // Not a swap in any disguise — nothing must put it in the Swaps or
        // Limit Orders tab, or hand it to a tracking service.
        XCTAssertNil(row.swapProvider)
        XCTAssertNil(row.swapTracking)
        XCTAssertFalse(row.isSwapRouted)
    }

    /// The regression, stated as the thing that must never appear: the
    /// trust-line limit, in ANY field of the row, in any form.
    ///
    /// Written as a sweep rather than one assertion per field so a new field
    /// added to `TransactionHistoryData` cannot quietly become the next place
    /// the limit leaks into.
    func testTheTrustLineLimitAppearsInNoFieldOfTheRow() {
        let row = makeRow()

        let fields: [String?] = [
            row.txHash, row.approveTxHash, row.coinTicker, row.coinLogo, row.coinChainLogo,
            row.amountCrypto, row.amountFiat, row.fromAddress, row.toAddress,
            row.toCoinTicker, row.toCoinLogo, row.toCoinChainLogo,
            row.toAmountCrypto, row.toAmountFiat, row.swapProvider,
            row.feeCrypto, row.feeFiat, row.network, row.explorerLink,
            row.estimatedTime, row.errorMessage
        ]

        for field in fields.compactMap({ $0 }) {
            XCTAssertFalse(
                field.contains(Self.limitDisplayValue),
                "the trust-line limit must not be persisted anywhere on the row — found in '\(field)'"
            )
        }
    }

    /// Guards the sweep above against passing vacuously. If the fixture ever
    /// stops producing the limit string, the sweep would pass no matter what the
    /// recorder does.
    func testTheFixtureReallyCarriesTheLimitTheSweepLooksFor() {
        let payload = makeDonePayload(
            amountCrypto: "\(Self.limitDisplayValue) RLUSD",
            keysignPayload: makeTrustSetPayload()
        )

        XCTAssertTrue(payload.amountCrypto.contains(Self.limitDisplayValue))
        XCTAssertEqual(
            RippleTrustLineLimit.defaultLimitDisplayValue(),
            Self.limitDisplayValue,
            "the limit this suite asserts against is the one the app actually signs"
        )
    }

    /// A trust-line row must render as an activation, not as a transfer: the
    /// expanded card layout is an amount → recipient diagram, and it has
    /// neither.
    func testTheActivationRowNeverUsesTheTransferLayout() {
        XCTAssertFalse(
            TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .trustLineActivation)
        )
        XCTAssertFalse(
            TransactionHistoryCardView.shouldExpand(status: .successful, type: .trustLineActivation)
        )
        // Unchanged for the types that DO move something.
        XCTAssertTrue(TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .send))
        XCTAssertTrue(TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .swap))
    }

    /// History and the done screen read from one string, so the receipt and the
    /// row cannot describe the same transaction differently.
    func testHistoryAndTheDoneScreenShareTheActivationCopy() throws {
        let hero = try XCTUnwrap(RippleTrustSetPresentation.hero(for: makeTrustSetPayload()))
        guard case .title(let text, let caption) = hero else {
            return XCTFail("a TrustSet receipt must not use an amount hero")
        }

        let row = makeRow()
        XCTAssertEqual(RippleTrustSetPresentation.activationTitle(ticker: row.coinTicker), text)
        XCTAssertEqual(row.toAddress, caption)
        XCTAssertFalse(text.contains(Self.limitDisplayValue))
    }

    /// The row's persisted `type` survives the SwiftData round trip. A raw value
    /// the reader doesn't recognise falls back to `.send` — silently restoring
    /// the transfer framing this whole type exists to escape.
    func testTheActivationTypeRoundTripsThroughItsRawValue() {
        XCTAssertEqual(
            TransactionHistoryType(rawValue: TransactionHistoryType.trustLineActivation.rawValue),
            .trustLineActivation
        )
        XCTAssertEqual(TransactionHistoryType.trustLineActivation.rawValue, "trustLineActivation")
    }

    // MARK: - Fixtures

    private func makeRow() -> TransactionHistoryData {
        TransactionHistoryRecorder.trustLineActivationRow(
            txHash: "TRUSTSETHASH",
            pubKeyECDSA: "pubkey-ecdsa",
            coin: makeCoin(tokenId: "\(Self.rlusdHex).\(Self.issuer)"),
            ticker: "RLUSD",
            issuer: Self.issuer,
            feeCrypto: "0.000012 XRP",
            feeFiat: "$0.00003",
            explorerLink: "https://xrpscan.com/tx/TRUSTSETHASH"
        )
    }

    private func makeCoin(tokenId: String) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .ripple,
                ticker: "TEST",
                logo: .empty,
                decimals: RippleIssuedCurrency.issuedCurrencyDecimals,
                priceProviderId: .empty,
                contractAddress: tokenId,
                isNativeToken: false
            ),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
    }

    private func makeDonePayload(
        amountCrypto: String,
        keysignPayload: KeysignPayload?,
        fromAddress: String = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
        hash: String = "TRUSTSETHASH",
        pubKeyECDSA: String = "pubkey-ecdsa",
        memo: String = "",
        verb: TransactionActionVerb = .send
    ) -> TransactionDonePayload {
        TransactionDonePayload(
            coin: keysignPayload?.coin ?? .example,
            amountCrypto: amountCrypto,
            amountFiat: "",
            hash: hash,
            explorerLink: "https://xrpscan.com/tx/TRUSTSETHASH",
            memo: memo,
            isSend: true,
            fromAddress: fromAddress,
            toAddress: Self.issuer,
            fee: FeeDisplay(crypto: "0.000012 XRP", fiat: "$0.00003"),
            keysignPayload: keysignPayload,
            pubKeyECDSA: pubKeyECDSA,
            verb: verb
        )
    }

    private func makeTrustSetPayload(
        tokenId: String? = nil,
        transactionType: VSTransactionType = .rippleTrustSet
    ) -> KeysignPayload {
        makePayload(
            coin: makeCoin(tokenId: tokenId ?? "\(Self.rlusdHex).\(Self.issuer)"),
            toAmount: RippleTrustLineLimit.defaultLimit,
            chainSpecific: .Ripple(
                sequence: 1,
                gas: 10,
                lastLedgerSequence: 100,
                transactionType: transactionType.rawValue
            )
        )
    }

    private func makeThorchainPayload(memo: String? = nil) -> KeysignPayload {
        makePayload(
            coin: .example,
            toAmount: BigInt(1000),
            chainSpecific: .THORChain(
                accountNumber: 1,
                sequence: 1,
                fee: 0,
                isDeposit: true,
                transactionType: 0
            ),
            memo: memo
        )
    }

    private func makePayload(
        coin: Coin,
        toAmount: BigInt,
        chainSpecific: BlockChainSpecific,
        memo: String? = nil
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: Self.issuer,
            toAmount: toAmount,
            chainSpecific: chainSpecific,
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pubkey-ecdsa",
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
}
