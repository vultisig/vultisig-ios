//
//  TronTransactionDecoderTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

@MainActor
final class TronTransactionDecoderTests: XCTestCase {

    /// Isolates unique-model fixtures from test ordering.
    private var storeToken: TestContextToken?

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(storeToken)
        storeToken = nil
        super.tearDown()
    }

    // MARK: - What it names

    func testFreezingForBandwidthIsAStakeWithItsAmount() {
        let decoded = SignedTransactionDecoder.decode(Self.payload(memo: "FREEZE:BANDWIDTH"))
        XCTAssertEqual(decoded.operation, .stake)
        XCTAssertEqual(decoded.amount, .units(BigInt(5_000_000), of: .chainNative))
        XCTAssertEqual(decoded.evidence, .memo)
    }

    func testFreezingForEnergyIsAlsoAStake() {
        XCTAssertEqual(SignedTransactionDecoder.decode(Self.payload(memo: "FREEZE:ENERGY")).operation, .stake)
    }

    func testUnfreezingIsAnUnstake() {
        for resource in ["BANDWIDTH", "ENERGY"] {
            let decoded = SignedTransactionDecoder.decode(Self.payload(memo: "UNFREEZE:\(resource)"))
            XCTAssertEqual(decoded.operation, .unstake, resource)
            XCTAssertEqual(decoded.amount, .units(BigInt(5_000_000), of: .chainNative), resource)
        }
    }

    /// Both devices must read the same transaction identically.
    func testTheReadingIsTheSameOnBothDevices() throws {
        let payload = Self.payload(memo: "FREEZE:ENERGY")
        let coSigner = SignedTransactionDecoder.decode(payload)
        let initiator = SignedTransactionDecoder.decode(
            InitiatingTransactionContent(Self.transaction(memo: "FREEZE:ENERGY"))
        )
        XCTAssertEqual(coSigner.operation, initiator.operation)
        XCTAssertEqual(coSigner.amount, initiator.amount)
        XCTAssertEqual(coSigner.evidence, initiator.evidence)
    }

    // MARK: - What it refuses

    /// Typed contract payloads outrank the staking memo in the signer.
    func testAContractPayloadBesideAStakingMemoIsRefused() {
        let transfer = TronTransferContractPayload(
            toAddress: "TRecipient", ownerAddress: "TOwner", amount: "5000000"
        )
        let spoofed = Self.payload(memo: "FREEZE:ENERGY", tronTransfer: transfer)

        XCTAssertEqual(
            SignedTransactionDecoder.decode(spoofed).operation, .unknown,
            "a transfer payload outranks the memo in the signer, so the memo must not name the transaction"
        )
    }

    func testASmartContractPayloadBesideAStakingMemoIsRefused() {
        let call = TronTriggerSmartContractPayload(
            ownerAddress: "TOwner", contractAddress: "TContract",
            callValue: nil, callTokenValue: nil, tokenId: nil, data: "deadbeef"
        )
        XCTAssertEqual(
            SignedTransactionDecoder.decode(Self.payload(memo: "UNFREEZE:BANDWIDTH", tronTrigger: call)).operation,
            .unknown
        )
    }

    /// Unknown or inexact resource names are rejected by the signer.
    func testAnUnknownResourceIsRefused() {
        for memo in ["FREEZE:CPU", "FREEZE:bandwidth", "FREEZE:", "FREEZE:BANDWIDTH ", "UNFREEZE:ENERGY!"] {
            XCTAssertEqual(
                SignedTransactionDecoder.decode(Self.payload(memo: memo)).operation, .unknown,
                memo
            )
        }
    }

    /// The grammar must not apply off TRON.
    func testTheGrammarDoesNotApplyOffTron() {
        let elsewhere = Self.payload(memo: "FREEZE:ENERGY", chain: .thorChain, ticker: "RUNE")
        XCTAssertEqual(SignedTransactionDecoder.decode(elsewhere).operation, .unknown)
    }

    func testAnOrdinaryTransferIsNotClaimed() {
        XCTAssertEqual(SignedTransactionDecoder.decode(Self.payload(memo: nil)).operation, .unknown)
    }

    /// Amounts outside the wire's `int64` are not stated.
    func testAnAmountTheSignerCouldNotEncodeIsNotStated() {
        let decoded = SignedTransactionDecoder.decode(
            Self.payload(memo: "FREEZE:ENERGY", amount: BigInt(Int64.max) + 1)
        )
        XCTAssertEqual(decoded.operation, .stake)
        XCTAssertEqual(decoded.amount, .unstated)
    }

    /// Swap routing outranks the memo.
    func testAStakingMemoBesideASwapPayloadIsRefused() {
        XCTAssertEqual(
            SignedTransactionDecoder.decode(Self.payload(memo: "FREEZE:ENERGY", withSwap: true)).operation,
            .unknown,
            "a swap payload is dispatched before the chain helper, so the memo describes nothing signed"
        )
    }

    /// Payload metadata cannot change the instruction's native asset.
    func testATokenDressedPayloadStillReadsAsTheChainsOwnCoin() {
        let decoded = SignedTransactionDecoder.decode(Self.payload(memo: "FREEZE:ENERGY", native: false))
        XCTAssertEqual(decoded.operation, .stake)
        XCTAssertEqual(
            decoded.amount, .units(BigInt(5_000_000), of: .chainNative),
            "the asset must come from the chain, not from what the payload calls itself"
        )
    }

    /// Rendering uses bundled TRX metadata, not the payload ticker.
    func testTheRenderedAmountUsesBundledChainMetadata() throws {
        let decoded = SignedTransactionDecoder.decode(Self.payload(memo: "FREEZE:ENERGY", native: false))
        let hero = try XCTUnwrap(
            DecodedTransactionPresentation.hero(for: decoded, coin: Self.coin(native: false))
        )
        guard case .send(_, let amount) = hero else {
            return XCTFail("a stated amount should render as a resolved single-sided figure")
        }
        XCTAssertEqual(amount.ticker, "TRX", "rendered against the payload's ticker instead of the chain's own")
    }

    // MARK: - Fixtures

    private static func coin(chain: Chain = .tron, ticker: String = "TRX", native: Bool = true) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: chain, ticker: ticker, logo: ticker.lowercased(), decimals: 6,
                priceProviderId: "tron",
                contractAddress: native ? "" : "TTokenContract",
                isNativeToken: native
            ),
            address: "TOwner",
            hexPublicKey: "00"
        )
    }

    private static func payload(
        memo: String?,
        chain: Chain = .tron,
        ticker: String = "TRX",
        amount: BigInt = BigInt(5_000_000),
        native: Bool = true,
        withSwap: Bool = false,
        tronTransfer: TronTransferContractPayload? = nil,
        tronTrigger: TronTriggerSmartContractPayload? = nil
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin(chain: chain, ticker: ticker, native: native),
            toAddress: "TOwner",
            toAmount: amount,
            chainSpecific: .Tron(timestamp: 0, expiration: 0, blockHeaderTimestamp: 0, blockHeaderNumber: 0,
                        blockHeaderVersion: 0, blockHeaderTxTrieRoot: "", blockHeaderParentHash: "",
                        blockHeaderWitnessAddress: "", gasFeeEstimation: 0),
            utxos: [],
            memo: memo,
            swapPayload: withSwap ? .thorchain(swapPayload()) : nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: tronTransfer,
            tronTriggerSmartContractPayload: tronTrigger,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private static func swapPayload() -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: "TOwner",
            fromCoin: coin(),
            toCoin: coin(),
            vaultAddress: "thor-vault",
            routerAddress: nil,
            fromAmount: BigInt(5_000_000),
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
            vault: TestStore.makeVault(pubKey: "test-pub-tron-\(memo)"),
            fromAddress: coin.address,
            toAddress: "TOwner",
            toAddressLabel: nil,
            amount: "5",
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
}
