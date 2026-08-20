//
//  THORChainTransactionDecoderTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

@MainActor
final class THORChainTransactionDecoderTests: XCTestCase {

    private var storeToken: TestContextToken?
    private var inboundVaults: InboundVaultCorroborating?

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeToken = try TestStore.installInMemoryContainer()
        inboundVaults = THORChainTransactionDecoder.inboundVaults
    }

    override func tearDown() {
        TestStore.restore(storeToken)
        storeToken = nil
        if let inboundVaults {
            THORChainTransactionDecoder.inboundVaults = inboundVaults
        }
        inboundVaults = nil
        super.tearDown()
    }

    // MARK: - What it names

    func testTheMemoGrammarNamesItsOperations() {
        let expected: [(memo: String, operation: DecodedOperation)] = [
            ("tcy+", .stake),
            ("tcy-:5006", .unstake),
            ("BOND:thor1node", .bond),
            ("UNBOND:thor1node:100", .unbond),
            ("LEAVE:thor1node", .leave),
            ("SECURE+:thor1dest", .securedAssetDeposit),
            ("SECURE-:thor1dest", .securedAssetWithdraw),
            ("m=<:100000000THOR.RUNE:15979057441BTC.BTC:0", .limitOrderCancel)
        ]

        for probe in expected {
            XCTAssertEqual(
                SignedTransactionDecoder.decode(Self.payload(memo: probe.memo)).operation,
                probe.operation,
                probe.memo
            )
        }
    }

    /// A staked withdrawal commits to a fraction, not a settled amount.
    func testAStakedWithdrawalIsAFractionNotAnAmount() {
        let decoded = SignedTransactionDecoder.decode(Self.payload(memo: "tcy-:5006"))
        XCTAssertEqual(decoded.operation, .unstake)
        XCTAssertEqual(decoded.amount, .fraction(basisPoints: 5006, of: .transactionCoin))
    }

    /// A memo-only withdrawal must not inherit its zero carrier amount.
    func testAStakedWithdrawalNeverReadsAsAZeroSend() {
        let decoded = SignedTransactionDecoder.decode(Self.payload(memo: "tcy-:5006", amount: .zero))
        XCTAssertNotEqual(decoded.operation, .transfer)
        XCTAssertEqual(decoded.operation, .unstake)
    }

    func testADepositStatesWhatItCarries() {
        let decoded = SignedTransactionDecoder.decode(Self.payload(memo: "tcy+", amount: BigInt(100_000_000)))
        XCTAssertEqual(decoded.amount, .units(BigInt(100_000_000), of: .transactionCoin))
    }

    /// A max send carries no figure: the signer derives it at signing time.
    func testAMaxSendDepositNamesNoAmount() {
        let decoded = SignedTransactionDecoder.decode(Self.payload(memo: "tcy+", sendMax: true))
        XCTAssertEqual(decoded.operation, .stake)
        XCTAssertEqual(decoded.amount, .unstated)
    }

    // MARK: - Provenance

    /// User-entered lookalike memos on unrelated chains lack provenance.
    func testTheGrammarDoesNotApplyToAnUnrelatedChain() {
        let elsewhere = Self.payload(memo: "tcy+", chain: .cardano, ticker: "ADA")
        XCTAssertEqual(SignedTransactionDecoder.decode(elsewhere).operation, .unknown)
    }

    /// An inbound deposit leaves another chain, so the swap payload is what
    /// corroborates that THORChain is the counterparty.
    func testAnInboundDepositIsReadThroughItsSwapPayload() {
        let inbound = Self.payload(memo: "SECURE+:thor1dest", chain: .bitcoin, ticker: "BTC", withThorSwap: true)
        XCTAssertEqual(SignedTransactionDecoder.decode(inbound).operation, .securedAssetDeposit)
    }

    func testInboundVaultFallbackDoesNotOverrideApproveOrAnotherSwap() {
        THORChainTransactionDecoder.inboundVaults = AlwaysInboundVaults()
        let coin = Self.coin(chain: .bitcoin, ticker: "BTC")

        let approve = Self.payload(
            memo: "SECURE+:thor1dest",
            chain: .bitcoin,
            ticker: "BTC",
            approve: ERC20ApprovePayload(amount: 1, spender: "router")
        )
        let otherSwap = Self.payload(
            memo: "SECURE+:thor1dest",
            chain: .bitcoin,
            ticker: "BTC",
            swap: .mayachain(Self.swapPayload(coin: coin))
        )

        XCTAssertEqual(SignedTransactionDecoder.decode(approve).operation, .unknown)
        XCTAssertEqual(SignedTransactionDecoder.decode(otherSwap).operation, .unknown)
    }

    // MARK: - What it refuses

    /// Opaque signed artifacts outrank flat memo sidecars.
    func testOpaqueSignedContentIsNotNamedByTheMemoBesideIt() {
        // Presence of opaque content is sufficient to make the sidecar inert.
        let opaque = Self.payload(
            memo: "tcy+",
            signData: .signDirect(
                SignDirect(bodyBytes: "", authInfoBytes: "", chainID: "thorchain-1", accountNumber: "0")
            )
        )
        XCTAssertEqual(SignedTransactionDecoder.decode(opaque).operation, .unknown)
    }

    func testAnUnparsedMemoIsNotASend() {
        XCTAssertEqual(SignedTransactionDecoder.decode(Self.payload(memo: "hello there")).operation, .unknown)
    }

    func testNoMemoIsNotAnOperation() {
        XCTAssertEqual(SignedTransactionDecoder.decode(Self.payload(memo: nil)).operation, .unknown)
    }

    // MARK: - Both devices

    func testTheReadingIsTheSameOnBothDevices() {
        for memo in ["tcy+", "tcy-:5006", "BOND:thor1node"] {
            let coSigner = SignedTransactionDecoder.decode(Self.payload(memo: memo))
            let initiator = SignedTransactionDecoder.decode(
                InitiatingTransactionContent(Self.transaction(memo: memo))
            )
            XCTAssertEqual(coSigner.operation, initiator.operation, memo)
            XCTAssertEqual(coSigner.amount, initiator.amount, memo)
        }
    }

    // MARK: - Fixtures

    private static func coin(chain: Chain = .thorChain, ticker: String = "TCY") -> Coin {
        Coin(
            asset: CoinMeta(
                chain: chain, ticker: ticker, logo: ticker.lowercased(), decimals: 8,
                priceProviderId: "thorchain", contractAddress: "", isNativeToken: true
            ),
            address: "thor1from",
            hexPublicKey: "00"
        )
    }

    private static func payload(
        memo: String?,
        chain: Chain = .thorChain,
        ticker: String = "TCY",
        amount: BigInt = BigInt(100_000_000),
        sendMax: Bool = false,
        withThorSwap: Bool = false,
        approve: ERC20ApprovePayload? = nil,
        swap: SwapPayload? = nil,
        signData: SignData? = nil
    ) -> KeysignPayload {
        let coin = coin(chain: chain, ticker: ticker)
        return KeysignPayload(
            coin: coin,
            toAddress: "thor1dest",
            toAmount: amount,
            chainSpecific: sendMax
                ? .UTXO(byteFee: BigInt(1), sendMaxAmount: true)
                : .THORChain(accountNumber: 0, sequence: 0, fee: 0, isDeposit: true),
            utxos: [],
            memo: memo,
            swapPayload: swap ?? (withThorSwap ? .thorchain(swapPayload(coin: coin)) : nil),
            approvePayload: approve,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: signData
        )
    }

    private static func swapPayload(coin: Coin) -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: "thor1from",
            fromCoin: coin,
            toCoin: coin,
            vaultAddress: "thor-vault",
            routerAddress: nil,
            fromAmount: BigInt(100_000_000),
            toAmountDecimal: 0,
            toAmountLimit: "0",
            streamingInterval: "0",
            streamingQuantity: "0",
            expirationTime: 0,
            isAffiliate: false
        )
    }

    private static func transaction(memo: String) -> SendTransaction {
        let coin = coin()
        return SendTransaction(
            coin: coin,
            vault: TestStore.makeVault(pubKey: "test-pub-thor-\(memo)"),
            fromAddress: coin.address,
            toAddress: "thor1dest",
            toAddressLabel: nil,
            amount: "1",
            amountInFiat: "0",
            memo: memo,
            gas: .zero,
            fee: .zero,
            feeMode: .normal,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: true,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin
        )
    }

    private struct AlwaysInboundVaults: InboundVaultCorroborating {
        func corroborates(destination _: String, chain _: Chain, isNative _: Bool) -> Bool { true }
    }
}
