//
//  TransactionDecoderTests.swift
//  VultisigAppTests
//
//  These pin four properties, in descending order of how much they matter.
//
//  1. A reading depends ONLY on what will be signed. Payload metadata an
//     initiator can change without changing a signed byte — decimals, ticker,
//     contract address — must not be able to move it. This is the property that
//     ruled out declaring the operation on the wire, and the one a decoder is
//     only worth having if it keeps.
//  2. A transaction that commits to a FRACTION is never described as a
//     quantity. That defect is where "You're sending 0 TCY" came from.
//  3. Both devices read the same transaction the same way.
//  4. Decoding never invents. Anything unreadable is `.unknown`, not a send.
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import XCTest

@MainActor
final class TransactionDecoderTests: XCTestCase {

    // MARK: - Only signed content decides

    /// ⚠️ The property the amount model exists for. `decimals` is serialized in
    /// the payload but never committed by the chain, so an initiator can change
    /// it freely.
    ///
    /// This pins the DECODED VALUE only, which is as far as decoding reaches. A
    /// presentation still has to scale those units to show them, so the exposure
    /// is moved to one place that can state it rather than removed outright —
    /// naming this test after the decoded value keeps that honest.
    func testTheDecodedValueIsUnchangedWhenUnsignedDecimalsChange() {
        let memo = "UNBOND:thor1node:150000000"
        let eight = decode(makePayload(memo: memo, amount: .zero, coin: thorCoin(decimals: 8)))
        let eighteen = decode(makePayload(memo: memo, amount: .zero, coin: thorCoin(decimals: 18)))

        XCTAssertEqual(eight.amount, eighteen.amount)
        XCTAssertEqual(eight.amount, .units(BigInt(150_000_000), of: .transactionCoin))
    }

    /// Shares are reported against the denom the SIGNED content names, so the
    /// same is true of them.
    func testShareAmountsAreReportedAgainstTheSignedDenom() throws {
        let decoded = decode(makePayload(memo: "unmerge:rune:250000000", amount: .zero))

        XCTAssertEqual(decoded.operation, .unmerge)
        XCTAssertEqual(decoded.amount, .units(BigInt(250_000_000), of: .denom("rune")))
    }

    // MARK: - Fractions are never quantities

    /// ⚠️ The regression this component exists for. `tcy-:5006` asks for 50.06%
    /// of whatever is staked at execution; the transaction's own amount is a
    /// literal zero. Reporting the zero is the bug.
    func testAFractionalWithdrawalDecodesAsAFraction() throws {
        let decoded = decode(makePayload(memo: "tcy-:5006", amount: .zero))

        XCTAssertEqual(decoded.operation, .unstake)
        XCTAssertEqual(decoded.amount, .fraction(basisPoints: 5006, of: .transactionCoin))
    }

    func testMayaWithdrawalDecodesAsAFractionToo() throws {
        let decoded = decode(makePayload(memo: "POOL-:2500", amount: .zero, coin: mayaCoin))
        XCTAssertEqual(decoded.amount, .fraction(basisPoints: 2500, of: .transactionCoin))
    }

    /// A memo asking for none of a position, or more than all of it, is refused
    /// rather than papered over with a plausible-looking fraction.
    func testAnOutOfRangeFractionIsRefused() {
        for bps in ["0", "10001", "notanumber"] {
            XCTAssertEqual(
                decode(makePayload(memo: "tcy-:\(bps)", amount: .zero)).operation,
                .unknown,
                "bps \(bps) should not produce a reading"
            )
        }
    }

    // MARK: - Never invents

    /// ⚠️ A memo nobody parses is NOT a send. Calling it one is inventing a
    /// reading, which is the failure this component exists to prevent.
    func testAnUnrecognisedMemoIsUnknownRatherThanATransfer() {
        let decoded = decode(makePayload(memo: "something nobody parses", amount: BigInt(100_000_000)))
        XCTAssertEqual(decoded.operation, .unknown)
        XCTAssertEqual(decoded.evidence, .unread)
    }

    /// ⚠️ A SignDoc IS the transaction. While nothing decodes one, `toAmount`
    /// and `toAddress` are free to disagree with it at no cost, so describing a
    /// transaction from them would describe something other than what is signed.
    func testAPayloadCarryingSignedDataIsNotDescribedFromItsOtherFields() {
        let decoded = decode(makePayload(
            memo: nil,
            amount: BigInt(100_000_000),
            signData: .signDirect(.empty)
        ))
        XCTAssertEqual(decoded.operation, .unknown)
    }

    /// A payload with nothing to say for itself, on the other hand, really is a
    /// transfer.
    func testAPlainPayloadWithNoMemoIsATransfer() {
        let decoded = decode(makePayload(memo: nil, amount: BigInt(100_000_000)))
        XCTAssertEqual(decoded.operation, .transfer)
        XCTAssertEqual(decoded.amount, .units(BigInt(100_000_000), of: .transactionCoin))
    }

    /// Arity is checked, so a truncated memo is not confidently claimed.
    func testATruncatedMemoIsNotClaimed() {
        for memo in ["BOND", "BOND:", "UNBOND:thor1node", "LEAVE:"] {
            XCTAssertEqual(
                decode(makePayload(memo: memo, amount: .zero)).operation,
                .unknown,
                "\(memo) should not be claimed"
            )
        }
    }

    // MARK: - A synthetic payload must not outrank the memo

    /// ⚠️ ERC-20 LP adds and SECURE+ deposits synthesize a `SwapPayload` purely
    /// so the legacy router path can build a `depositWithExpiry` — their own
    /// builders say they are deposits, not swaps. An earlier revision asked the
    /// swap payload first and announced them as swaps on the co-signer, while
    /// the initiator, which has no synthesized payload yet, still said transfer.
    /// The memo is what the chain reads, so the memo answers first.
    func testASynthesizedSwapPayloadDoesNotOutrankTheMemo() throws {
        let decoded = decode(makePayload(
            memo: "SECURE+:thor1dest",
            amount: BigInt(100_000_000),
            swap: .thorchain(THORChainSwapPayload(
                fromAddress: "0xfrom",
                fromCoin: .example,
                toCoin: .example,
                vaultAddress: "0xvault",
                routerAddress: nil,
                fromAmount: BigInt(100_000_000),
                toAmountDecimal: 1,
                toAmountLimit: "0",
                streamingInterval: "0",
                streamingQuantity: "0",
                expirationTime: 0,
                isAffiliate: false
            ))
        ))

        XCTAssertEqual(decoded.operation, .securedAssetDeposit)
        XCTAssertEqual(decoded.evidence, .memo)
    }

    // MARK: - The grammars

    /// ⚠️ THORChain's node bond and Rujira's staking bond differ by one
    /// uppercase letter and put a different kind of party in the same field.
    /// Case-folding made the Rujira branch unreachable and named a contract as
    /// though it were a node.
    func testTheTwoBondSpellingsAreDifferentOperations() throws {
        let node = decode(makePayload(memo: "BOND:thor1node", amount: BigInt(100_000_000)))
        let rujira = decode(makePayload(memo: "bond:thor1contract:250000000", amount: .zero))

        XCTAssertEqual(node.operation, .bond)
        XCTAssertEqual(node.counterparty, .node("thor1node"))

        XCTAssertEqual(rujira.operation, .stake)
        XCTAssertEqual(rujira.counterparty, .contract("thor1contract"))
        XCTAssertEqual(rujira.amount, .units(BigInt(250_000_000), of: .denom("thor1contract")))
    }

    func testARebondIsRecognised() {
        let decoded = decode(makePayload(memo: "REBOND:thor1node:thor1new", amount: .zero))
        XCTAssertEqual(decoded.operation, .rebond)
        XCTAssertEqual(decoded.counterparty, .node("thor1node"))
    }

    func testSecuredAssetMemosAreRecognised() {
        XCTAssertEqual(
            decode(makePayload(memo: "SECURE+:thor1dest", amount: BigInt(1))).operation,
            .securedAssetDeposit
        )
        XCTAssertEqual(
            decode(makePayload(memo: "SECURE-:thor1dest", amount: BigInt(1))).operation,
            .securedAssetWithdraw
        )
    }

    // MARK: - Provenance

    /// ⚠️ THORChain's inbound memos are sent FROM the asset's own chain, so the
    /// grammar cannot be scoped to `.thorChain`. But a memo merely RESEMBLING
    /// that grammar proves nothing — so it applies off-chain only when signed
    /// content corroborates that a THORChain vault is the destination, which is
    /// what the router-deposit shim provides.
    func testAnInboundMemoIsReadWhenSignedContentNamesAThorchainVault() {
        let decoded = decode(makePayload(
            memo: "+:BTC.BTC",
            amount: BigInt(100_000_000),
            coin: bitcoinCoin,
            swap: .thorchain(thorchainSwap)
        ))
        XCTAssertEqual(decoded.operation, .addLiquidity)
        XCTAssertEqual(decoded.counterparty, .pool("BTC.BTC"))
    }

    /// ⚠️ The other half, and the reason the grammar cannot simply be global:
    /// `FunctionCallCustom` lets a user type any memo at all, so an arbitrary
    /// `+:foo` on an unrelated chain was being claimed as an LP add purely
    /// because of how the string looked.
    func testAThorchainShapedMemoOnAnUnrelatedChainIsNotClaimed() {
        for memo in ["+:foo", "-:foo:100", "BOND:anything", "SECURE+:anything"] {
            XCTAssertEqual(
                decode(makePayload(memo: memo, amount: BigInt(1), coin: bitcoinCoin)).operation,
                .unknown,
                "\(memo) must not be claimed without provenance"
            )
        }
    }

    /// A contract call is executed BY THORChain, so it cannot have arrived
    /// inbound from elsewhere — inspecting a foreign chain's wasm with this
    /// grammar is how an unrelated contract came to read as a Rujira operation.
    ///
    /// It is still a contract call, though, and saying so is not a guess: the
    /// execute message and its address are both in the payload. Only the Rujira
    /// MEANING is refused. Falling through to `.transfer` — as this did until a
    /// test caught it — would have described an arbitrary contract execution as
    /// an ordinary payment.
    func testAForeignChainsContractCallIsNamedButNotInterpreted() throws {
        let wasm = WasmExecuteContractPayload(
            senderAddress: "sender",
            contractAddress: "somecontract",
            executeMsg: #"{"deposit":{}}"#,
            coins: [CosmosCoin(amount: "100", denom: "foo")]
        )
        let decoded = decode(makePayload(memo: nil, amount: .zero, coin: bitcoinCoin, wasm: wasm))

        XCTAssertEqual(decoded.operation, .contractCall)
        XCTAssertNotEqual(decoded.operation, .stake, "the Rujira reading must not apply off THORChain")
        XCTAssertEqual(decoded.counterparty, .contract("somecontract"))
        XCTAssertEqual(decoded.amount, .unstated)
    }

    /// ⚠️ THORNode lowercases a memo's head before parsing, and the published
    /// grammar spells these uppercase — so case-sensitive matching silently
    /// dropped memos another client had every right to send.
    func testHeadsAreCaseFolded() {
        XCTAssertEqual(decode(makePayload(memo: "TCY-:5006", amount: .zero)).operation, .unstake)
        XCTAssertEqual(decode(makePayload(memo: "tcy-:5006", amount: .zero)).operation, .unstake)
        XCTAssertEqual(decode(makePayload(memo: "MERGE:rune", amount: BigInt(1))).operation, .merge)
    }

    /// ⚠️ A single-sided withdrawal appends the asset — `-:POOL:BPS:ASSET` — and
    /// reading basis points from the LAST field refused that valid memo.
    func testASingleSidedWithdrawalIsNotRefused() throws {
        let decoded = decode(makePayload(memo: "-:BTC.BTC:5000:BTC.BTC", amount: .zero))
        XCTAssertEqual(decoded.operation, .removeLiquidity)
        XCTAssertEqual(decoded.amount, .fraction(basisPoints: 5000, of: .transactionCoin))
    }

    /// MAYAChain puts the node in the fourth field, and its bonded quantity is
    /// not the transaction's CACAO carrier — so it states no amount at all.
    func testAMayaBondNamesItsNodeAndStatesNoAmount() throws {
        let decoded = decode(
            makePayload(memo: "BOND:CACAO:100:maya1node", amount: BigInt(100_000_000), coin: mayaCoin)
        )
        XCTAssertEqual(decoded.operation, .bond)
        XCTAssertEqual(decoded.counterparty, .node("maya1node"))
        XCTAssertEqual(decoded.amount, .unstated)
    }

    func testASwitchIsDecodedOnTheChainItLeavesFrom() {
        XCTAssertEqual(
            decode(makePayload(memo: "SWITCH:thor1self", amount: BigInt(1), coin: gaiaCoin)).operation,
            .switchChain
        )
    }

    func testADydxVoteMovesNothing() {
        let decoded = decode(makePayload(memo: "DYDX_VOTE:YES:42", amount: .zero, coin: dydxCoin))
        XCTAssertEqual(decoded.operation, .vote)
        XCTAssertEqual(decoded.amount, .unstated)
    }

    func testLimitOrderHeadsAreMatchedExactly() {
        XCTAssertEqual(
            decode(makePayload(memo: "m=<:100000000THOR.RUNE:1BTC.BTC:0", amount: .zero)).operation,
            .limitOrderCancel
        )
        XCTAssertEqual(
            decode(makePayload(memo: "=<:BTC.BTC:bc1q:16e8/1200/0::0", amount: BigInt(1))).operation,
            .limitOrderPlacement
        )
    }

    // MARK: - Contract calls

    /// ⚠️ A yVault operation hides its action inside a BASE64 envelope, so
    /// substring-matching the outer string finds nothing and every mint and
    /// redeem read as an opaque contract call.
    func testAYVaultDepositIsReadThroughItsBase64Envelope() throws {
        let decoded = decode(makePayload(memo: nil, amount: .zero, wasm: vaultWasm(#"{"deposit":{}}"#)))
        XCTAssertEqual(decoded.operation, .mint)
    }

    /// ⚠️ A vault deposit attaches what it SPENDS. What it mints is settled at
    /// execution and appears nowhere in the signed content, so naming the input
    /// beside "mint" would quote a figure for a quantity nobody knows.
    func testAMintStatesNoAmount() throws {
        let decoded = decode(makePayload(memo: nil, amount: .zero, wasm: vaultWasm(#"{"deposit":{}}"#)))
        XCTAssertEqual(decoded.amount, .unstated)
    }

    func testAYVaultWithdrawReadsAsARedeem() throws {
        let decoded = decode(makePayload(
            memo: nil, amount: .zero, wasm: vaultWasm(#"{"withdraw":{"slippage":"0.01"}}"#)
        ))
        XCTAssertEqual(decoded.operation, .redeem)
    }

    /// A parameter must never be mistaken for the action.
    func testAnActionsParametersAreNotMistakenForTheAction() throws {
        let wasm = WasmExecuteContractPayload(
            senderAddress: "thor1sender",
            contractAddress: "thor1contract",
            executeMsg: #"{"withdraw":{"slippage":"0.01"}}"#,
            coins: [CosmosCoin(amount: "100000000", denom: "TCY")]
        )
        XCTAssertEqual(decode(makePayload(memo: nil, amount: .zero, wasm: wasm)).operation, .unstake)
    }

    func testALiquidUnbondReportsTheSharesItAttaches() throws {
        let wasm = WasmExecuteContractPayload(
            senderAddress: "thor1sender",
            contractAddress: "thor1contract",
            executeMsg: #"{ "liquid": { "unbond": {} } }"#,
            coins: [CosmosCoin(amount: "300000000", denom: "x/staking-tcy")]
        )
        let decoded = decode(makePayload(memo: nil, amount: .zero, wasm: wasm))

        XCTAssertEqual(decoded.operation, .unstake)
        XCTAssertEqual(decoded.amount, .units(BigInt(300_000_000), of: .denom("x/staking-tcy")))
    }

    /// ⚠️ `funds` is a repeated field, so a message can attach several denoms.
    /// Reading only the first would announce one of them as though it were the
    /// whole quantity — a partial figure presented as a complete one, which is
    /// the same class of wrong number as the zero this exists to remove.
    func testAMultiCoinFundSetStatesNoQuantity() throws {
        let wasm = WasmExecuteContractPayload(
            senderAddress: "thor1sender",
            contractAddress: "thor1contract",
            executeMsg: #"{ "liquid": { "unbond": {} } }"#,
            coins: [
                CosmosCoin(amount: "300000000", denom: "x/staking-tcy"),
                CosmosCoin(amount: "100000000", denom: "x/staking-ruji")
            ]
        )
        let decoded = decode(makePayload(memo: nil, amount: .zero, wasm: wasm))

        XCTAssertEqual(decoded.operation, .unstake, "the action is still known")
        XCTAssertEqual(decoded.amount, .unstated, "but no single coin is the quantity")
    }

    /// A memo naming a zero or negative amount is not a confident reading of a
    /// quantity, any more than an out-of-range fraction is.
    func testAnUnbondWithNoRealAmountIsNotClaimed() {
        for units in ["0", "-5", "notanumber"] {
            XCTAssertEqual(
                decode(makePayload(memo: "UNBOND:thor1node:\(units)", amount: .zero)).operation,
                .unknown,
                "UNBOND with \(units) should not be claimed"
            )
        }
    }

    /// ⚠️ Swift dictionary order is undefined, so a message naming two actions
    /// had no defined winner and two devices could read the same bytes
    /// differently. Ambiguity is refused rather than resolved.
    func testAnAmbiguousExecuteMessageIsRefusedRatherThanGuessed() throws {
        let wasm = WasmExecuteContractPayload(
            senderAddress: "thor1sender",
            contractAddress: "thor1contract",
            executeMsg: #"{"bond":{},"withdraw":{}}"#,
            coins: []
        )
        XCTAssertEqual(decode(makePayload(memo: nil, amount: .zero, wasm: wasm)).operation, .contractCall)
    }

    // MARK: - Evidence

    func testEvidenceIsOrderedStrongestFirst() {
        XCTAssertTrue(DecodedEvidence.signedData < .wasmExecuteMsg)
        XCTAssertTrue(DecodedEvidence.wasmExecuteMsg < .memo)
        XCTAssertTrue(DecodedEvidence.memo < .wireTransactionType)
        XCTAssertTrue(DecodedEvidence.wireTransactionType < .unread)
        XCTAssertTrue(DecodedEvidence.memo.isNoWeaker(than: .wireTransactionType))
        XCTAssertFalse(DecodedEvidence.wireTransactionType.isNoWeaker(than: .memo))
    }

    // MARK: - The two devices cannot drift apart

    /// ⚠️ The architectural property: an initiator holds a `SendTransaction` and
    /// a co-signer holds a `KeysignPayload`, and decoding through one surface is
    /// what stops them describing the same transaction differently.
    func testBothDevicesReadTheSameTransactionIdentically() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        for memo in ["UNBOND:thor1node:150000000", "tcy-:5006", "SECURE+:thor1dest", "+:BTC.BTC"] {
            let fromPayload = decode(makePayload(memo: memo, amount: BigInt(100_000_000)))
            let fromTransaction = SignedTransactionDecoder.decode(
                InitiatingTransactionContent(makeSendTransaction(memo: memo, amount: "1"))
            )

            XCTAssertEqual(fromPayload.operation, fromTransaction.operation, memo)
            XCTAssertEqual(fromPayload.amount, fromTransaction.amount, memo)
            XCTAssertEqual(fromPayload.counterparty, fromTransaction.counterparty, memo)
            XCTAssertEqual(fromPayload.evidence, fromTransaction.evidence, memo)
        }
    }

    /// ⚠️ The divergence the memo-only parity test could not see. A Cosmos
    /// delegate carries its intent in `cosmosStakingPayload`, which becomes a
    /// `signDirect` SignDoc during payload construction. Keying the refusal on
    /// the BUILT artefact meant the co-signer refused while the initiator, which
    /// has not built one yet, called the same transaction a transfer.
    ///
    /// Both sides now answer the same question — "will opaque signed content
    /// replace these fields?" — from what each of them holds.
    func testBothDevicesRefuseATransactionNeitherCanRead() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let fromPayload = decode(makePayload(
            memo: nil, amount: BigInt(100_000_000), signData: .signDirect(.empty)
        ))
        let fromTransaction = SignedTransactionDecoder.decode(
            InitiatingTransactionContent(makeSendTransaction(
                memo: "",
                amount: "1",
                cosmosStaking: .delegate(
                    validator: "cosmosvaloper1x", denom: "uatom", amount: "100000000"
                )
            ))
        )

        XCTAssertEqual(fromPayload.operation, .unknown)
        XCTAssertEqual(fromTransaction.operation, .unknown, "the initiator must refuse in step")
    }

    // MARK: - Fixtures

    private func decode(_ payload: KeysignPayload) -> DecodedTransaction {
        SignedTransactionDecoder.decode(payload)
    }

    private func thorCoin(decimals: Int = 8) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .thorChain, ticker: "TCY", logo: "tcy", decimals: decimals,
                priceProviderId: "tcy", contractAddress: "", isNativeToken: false
            ),
            address: "thor1from",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private var mayaCoin: Coin {
        Coin(
            asset: CoinMeta(
                chain: .mayaChain, ticker: "CACAO", logo: "cacao", decimals: 10,
                priceProviderId: "cacao", contractAddress: "", isNativeToken: true
            ),
            address: "maya1from",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private var gaiaCoin: Coin {
        Coin(
            asset: CoinMeta(
                chain: .gaiaChain, ticker: "ATOM", logo: "atom", decimals: 6,
                priceProviderId: "cosmos", contractAddress: "", isNativeToken: true
            ),
            address: "cosmos1from",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private var dydxCoin: Coin {
        Coin(
            asset: CoinMeta(
                chain: .dydx, ticker: "DYDX", logo: "dydx", decimals: 18,
                priceProviderId: "dydx", contractAddress: "", isNativeToken: true
            ),
            address: "dydx1from",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private var bitcoinCoin: Coin {
        Coin(
            asset: CoinMeta(
                chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8,
                priceProviderId: "bitcoin", contractAddress: "", isNativeToken: true
            ),
            address: "bc1qfrom",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private func vaultWasm(_ inner: String) -> WasmExecuteContractPayload {
        let encoded = Data(inner.utf8).base64EncodedString()
        return WasmExecuteContractPayload(
            senderAddress: "thor1sender",
            contractAddress: "thor1affiliate",
            executeMsg: #"{"execute":{"contract_addr":"thor1vault","msg":"\#(encoded)","affiliate":["thor1aff",50]}}"#,
            coins: [CosmosCoin(amount: "100000000", denom: "tcy")]
        )
    }

    private func makePayload(
        memo: String?,
        amount: BigInt,
        coin: Coin? = nil,
        wasm: WasmExecuteContractPayload? = nil,
        swap: SwapPayload? = nil,
        signData: SignData? = nil
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin ?? thorCoin(),
            toAddress: "thor1to",
            toAmount: amount,
            chainSpecific: .THORChain(
                accountNumber: 1, sequence: 1, fee: 0, isDeposit: true, transactionType: 0
            ),
            utxos: [],
            memo: memo,
            swapPayload: swap,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: wasm,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: signData
        )
    }

    private var thorchainSwap: THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: "0xfrom",
            fromCoin: .example,
            toCoin: .example,
            vaultAddress: "thor1vault",
            routerAddress: nil,
            fromAmount: BigInt(100_000_000),
            toAmountDecimal: 1,
            toAmountLimit: "0",
            streamingInterval: "0",
            streamingQuantity: "0",
            expirationTime: 0,
            isAffiliate: false
        )
    }

    /// ⚠️ Each transaction gets its own vault identity. The parity test builds
    /// one per memo inside a single container, and `Vault`'s unique attributes
    /// make a second fixture with the same key upsert over the first rather
    /// than sit beside it.
    private func makeSendTransaction(
        memo: String,
        amount: String,
        cosmosStaking: CosmosStakingPayload? = nil
    ) -> SendTransaction {
        let coin = thorCoin()
        // Derived from the memo rather than hashed: `hashValue` is seeded per
        // process, so it would name a different vault on every run and make a
        // failure impossible to reproduce from the message alone.
        let identity = "test-pub-decoder-\(memo)"
        return SendTransaction(
            coin: coin,
            vault: TestStore.makeVault(pubKey: identity),
            fromAddress: coin.address,
            toAddress: "thor1to",
            toAddressLabel: nil,
            amount: amount,
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
            feeCoin: coin,
            cosmosStakingPayload: cosmosStaking
        )
    }
}
