//
//  AddLPTransactionBuilderTests.swift
//  VultisigAppTests
//
//  The memo, the attached amount and — the reason this migration exists — the
//  recipient.
//
//  `toAddress` used to return `.empty` under a comment claiming it returned the
//  inbound address. Every assertion here that names a real address is an
//  assertion that could not have been written before.
//

import BigInt
import VultisigCommonData
import XCTest
@testable import VultisigApp

@MainActor
final class AddLPTransactionBuilderTests: XCTestCase {

    private func builder(
        coin: Coin,
        amount: String,
        pool: String,
        pairedAddress: String?,
        toAddress: String,
        sendMaxAmount: Bool = false
    ) -> AddLPTransactionBuilder {
        AddLPTransactionBuilder(
            coin: coin,
            amount: amount,
            poolName: pool,
            pairedAddress: pairedAddress,
            sendMaxAmount: sendMaxAmount,
            toAddress: toAddress
        )
    }

    // MARK: - Memo

    /// Carried from the deleted `FunctionCallAddThorLPTests`: the memo is
    /// `AddLPMemoData`'s encoding, and the paired address is present only when
    /// non-empty.
    func testMemoNamesThePoolAndThePairedAddress() {
        let memo = builder(
            coin: AddLPFixture.bitcoin(),
            amount: "0.5",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.btcVault
        ).memo

        XCTAssertEqual(memo, "+:BTC.BTC:\(AddLPFixture.thorAddress)")
    }

    func testMemoOmitsAnEmptyPairedAddress() {
        XCTAssertEqual(
            builder(
                coin: AddLPFixture.rune(),
                amount: "1",
                pool: AddLPFixture.btcPool,
                pairedAddress: "",
                toAddress: .empty
            ).memo,
            "+:BTC.BTC"
        )
        XCTAssertEqual(
            builder(
                coin: AddLPFixture.rune(),
                amount: "1",
                pool: AddLPFixture.btcPool,
                pairedAddress: nil,
                toAddress: .empty
            ).memo,
            "+:BTC.BTC"
        )
    }

    /// The contract suffix is part of what THORChain calls the pool, so it must
    /// survive into the memo. Stripping it — which the display name does — would
    /// name a pool that does not exist.
    func testMemoCarriesTheContractSuffixedPoolName() {
        XCTAssertEqual(
            builder(
                coin: AddLPFixture.usdc(),
                amount: "10",
                pool: AddLPFixture.usdcPool,
                pairedAddress: AddLPFixture.thorAddress,
                toAddress: AddLPFixture.ethRouter
            ).memo,
            "+:\(AddLPFixture.usdcPool):\(AddLPFixture.thorAddress)"
        )
    }

    /// Carried from the deleted legacy test.
    func testMemoDictionaryCarriesThePoolThePairedAddressAndTheMemo() {
        let dictionary = builder(
            coin: AddLPFixture.bitcoin(),
            amount: "0.5",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.btcVault
        ).memoFunctionDictionary.allItems()

        XCTAssertEqual(dictionary["pool"], AddLPFixture.btcPool)
        XCTAssertEqual(dictionary["pairedAddress"], AddLPFixture.thorAddress)
        XCTAssertEqual(dictionary["memo"], "+:BTC.BTC:\(AddLPFixture.thorAddress)")
        XCTAssertEqual(dictionary.count, 3)
    }

    /// `pool` is what marks the transaction an LP add at the signing boundary —
    /// `ThorchainRouterDepositBuilder.synthesizeRouterDeposit` keys off exactly
    /// this entry to decide whether an ERC-20 deposit gets its router shim.
    func testTheMemoDictionaryMarksTheTransactionAnLPAdd() {
        let tx = builder(
            coin: AddLPFixture.usdc(),
            amount: "10",
            pool: AddLPFixture.usdcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.ethRouter
        ).buildSendTransaction(vault: .example)

        XCTAssertNotNil(tx.memoFunctionDictionary["pool"])
    }

    // MARK: - The recipient

    /// ⚠️ The whole point. A native L1 deposit is a transfer to THORChain's
    /// inbound VAULT.
    func testANativeDepositIsSentToTheInboundVault() {
        let tx = builder(
            coin: AddLPFixture.bitcoin(),
            amount: "0.5",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.btcVault
        ).buildSendTransaction(vault: .example)

        XCTAssertEqual(tx.toAddress, AddLPFixture.btcVault)
        XCTAssertNotEqual(tx.toAddress, .empty, "the builder used to hardcode an empty recipient")
    }

    /// ⚠️ An ERC-20 deposit goes to the ROUTER, which is also the spender the
    /// approval names — `synthesizeRouterDeposit` builds
    /// `ERC20ApprovePayload(spender: tx.toAddress)`, so the two are the same
    /// address by construction rather than by two independent resolutions.
    func testAnERC20DepositIsSentToTheRouter() {
        let tx = builder(
            coin: AddLPFixture.usdc(),
            amount: "10",
            pool: AddLPFixture.usdcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.ethRouter
        ).buildSendTransaction(vault: .example)

        XCTAssertEqual(tx.toAddress, AddLPFixture.ethRouter)
        XCTAssertNotEqual(tx.toAddress, AddLPFixture.ethVault, "approving the inbound vault as a spender is the bug")
    }

    /// A protocol-native deposit rides a `MsgDeposit` and names no recipient, so
    /// the empty string is a real answer here — which is exactly why the view
    /// model may not use emptiness to mean "not resolved yet".
    func testAProtocolNativeDepositNamesNoRecipient() {
        let tx = builder(
            coin: AddLPFixture.rune(),
            amount: "1",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.btcVault,
            toAddress: .empty
        ).buildSendTransaction(vault: .example)

        XCTAssertEqual(tx.toAddress, .empty)
    }

    // MARK: - The `buildSendTransaction` boundary

    func testTheBuiltTransactionCarriesTheAmountAndTypeUnchanged() {
        let coin = AddLPFixture.bitcoin()
        let tx = builder(
            coin: coin,
            amount: "0.5",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.btcVault
        ).buildSendTransaction(vault: .example)

        XCTAssertEqual(tx.amount, "0.5")
        XCTAssertEqual(tx.amountInRaw, BigInt(50_000_000), "the builder's amount is a human decimal")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertNil(tx.cosmosStakingPayload)
    }

    func testSendMaxTravelsToTheTransaction() {
        let tx = builder(
            coin: AddLPFixture.bitcoin(),
            amount: "1",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.btcVault,
            sendMaxAmount: true
        ).buildSendTransaction(vault: .example)

        XCTAssertTrue(tx.sendMaxAmount)
    }

    /// ⚠️ The approval and the deposit must name ONE address.
    ///
    /// `ThorchainRouterDepositBuilder.synthesizeRouterDeposit` builds the
    /// approval's spender AND the router the deposit is built against from
    /// `tx.toAddress`, so the two cannot disagree. This pins the half that is
    /// reachable without a network: a deposit that needs no approval gets no
    /// router shim either, which is what stops an ERC-20 -> native pool switch
    /// signing a plain transfer at the router contract.
    func testANativeDepositSynthesizesNoRouterShim() async throws {
        let tx = builder(
            coin: AddLPFixture.bitcoin(),
            amount: "0.5",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.btcVault
        ).buildSendTransaction(vault: .example)

        let (swapPayload, approvePayload) = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(tx: tx)

        XCTAssertNil(swapPayload)
        XCTAssertNil(approvePayload)
    }

    /// An LP add with no resolved recipient must not produce an approval for an
    /// empty spender.
    func testADepositWithNoRecipientSynthesizesNoRouterShim() async throws {
        let tx = builder(
            coin: AddLPFixture.usdc(),
            amount: "10",
            pool: AddLPFixture.usdcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: .empty
        ).buildSendTransaction(vault: .example)

        let (swapPayload, approvePayload) = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(tx: tx)

        XCTAssertNil(swapPayload)
        XCTAssertNil(approvePayload)
    }

    // MARK: - The disclosed fee

    /// ⚠️ Add-LP is the first EVM operation on this pipeline, and
    /// `buildSendTransaction` hardcodes `fee: .zero` while
    /// `SendCryptoLogic.displayFee` reads `fee` — not `gas` — on EVM. Without
    /// the priced hand-off an Ethereum user approves a network fee of zero and
    /// is then charged a real one.
    ///
    /// 120,000 gas at 1.32 gwei is 0.0001584 ETH. The value is pinned, not
    /// merely asserted non-zero: the gas PRICE alone passes `> 0` and is
    /// 100,000× too small.
    func testAnEvmAddLPDisclosesTheRealFeeOnVerify() async {
        let evmChainSpecific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: BigInt(1_320_000_000),
            priorityFeeWei: BigInt(100_000_000),
            nonce: 0,
            gasLimit: BigInt(120_000)
        )
        let pricer = FunctionCallFeePricer(
            interactor: MockSendInteractor(),
            fetchSigningChainSpecific: { _ in evmChainSpecific }
        )

        let priced = await builder(
            coin: AddLPFixture.ether(),
            amount: "0.5",
            pool: AddLPFixture.ethPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.ethVault
        ).buildPricedSendTransaction(vault: .example, pricer: pricer)

        XCTAssertEqual(
            SendCryptoLogic.displayFee(coin: priced.coin, gas: priced.gas, fee: priced.fee),
            BigInt(158_400_000_000_000)
        )
        XCTAssertEqual(priced.fee, BigInt(158_400_000_000_000))
        XCTAssertNotEqual(priced.fee, .zero, "an EVM fee row reads `fee`, which the unpriced build leaves at zero")
    }

    /// ⚠️ The same defect on UTXO, where `chainSpecific` carries a sat/vB RATE
    /// rather than a total, so even copying `gas` discloses the wrong thing.
    /// The disclosed figure is what the planned transaction pays.
    func testAUtxoAddLPDisclosesTheRealFeeOnVerify() async {
        let byteRate = BigInt(12)
        let plannedFee = BigInt(3_000)
        let mock = MockSendInteractor()
        mock.fetchChainSpecificStub = { _ in .UTXO(byteFee: byteRate, sendMaxAmount: false) }
        mock.calculatePlanFeeStub = { _, _ in plannedFee }

        let priced = await builder(
            coin: AddLPFixture.bitcoin(),
            amount: "0.01",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.btcVault
        ).buildPricedSendTransaction(vault: .example, pricer: FunctionCallFeePricer(interactor: mock))

        XCTAssertEqual(
            SendCryptoLogic.displayFee(coin: priced.coin, gas: priced.gas, fee: priced.fee),
            plannedFee
        )
        XCTAssertEqual(priced.fee, plannedFee)
        XCTAssertNotEqual(priced.fee, byteRate, "12 sat/vB is a rate, not a fee")
    }

    /// The fee is priced against THIS deposit — its memo, its recipient, its
    /// amount — not against a bare probe transfer. On EVM the gas limit of a
    /// router `depositWithExpiry` is nothing like a plain transfer's.
    func testTheFeeIsPricedAgainstTheDepositItself() async {
        var fetched: [SendTransaction] = []
        let pricer = FunctionCallFeePricer(
            interactor: MockSendInteractor(),
            fetchSigningChainSpecific: { tx in
                fetched.append(tx)
                return .Ethereum(
                    maxFeePerGasWei: BigInt(1_320_000_000),
                    priorityFeeWei: BigInt(100_000_000),
                    nonce: 0,
                    gasLimit: BigInt(120_000)
                )
            }
        )

        _ = await builder(
            coin: AddLPFixture.usdc(),
            amount: "10",
            pool: AddLPFixture.usdcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.ethRouter
        ).buildPricedSendTransaction(vault: .example, pricer: pricer)

        XCTAssertEqual(fetched.first?.toAddress, AddLPFixture.ethRouter)
        XCTAssertEqual(fetched.first?.memo, "+:\(AddLPFixture.usdcPool):\(AddLPFixture.thorAddress)")
    }
}
