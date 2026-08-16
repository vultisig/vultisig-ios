//
//  FunctionTransactionFeePricerTests.swift
//  VultisigAppTests
//
//  What the Verify screen says a function call costs, on the chains where it
//  used to say nothing.
//

import BigInt
import VultisigCommonData
import XCTest
@testable import VultisigApp

/// ⚠️ These pin the DISCLOSED figure — `SendCryptoLogic.displayFee`, the exact
/// value the fee row and the fiat figure beside it are derived from — not just
/// "something non-zero". A wrong fee passes a `> 0` assertion and is still a
/// wrong fee on the screen where the user agrees to pay it.
///
/// The defect these cover: every seam between a function-call form and Verify
/// fetched the chain-specific data and copied `chainSpecific.gas` alone.
/// `displayFee` reads `fee` on EVM, UTXO and Cardano, so those three disclosed
/// `0` — and signing re-fetched a real fee and charged it. Nothing downstream of
/// `FunctionTransactionRoute.verify` re-resolves the figures for display, so the
/// hand-off is the only chance to get them right.
@MainActor
final class FunctionTransactionFeePricerTests: XCTestCase {

    // MARK: - Fixtures

    private static let ether: Coin = {
        let asset = CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "0xsender", hexPublicKey: "HexPublicKeyExample")
    }()

    private static let bitcoin: Coin = {
        let asset = CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "btc",
            decimals: 8,
            priceProviderId: "bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "bc1sender", hexPublicKey: "HexPublicKeyExample")
    }()

    private static let cardano: Coin = {
        let asset = CoinMeta(
            chain: .cardano,
            ticker: "ADA",
            logo: "ada",
            decimals: 6,
            priceProviderId: "cardano",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "addr1sender", hexPublicKey: "HexPublicKeyExample")
    }()

    private static let rune: Coin = {
        let asset = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "thor1sender", hexPublicKey: "HexPublicKeyExample")
    }()

    /// A THORChain LP-add memo — the operation the migration is about to move
    /// onto this pipeline from Ethereum and Bitcoin.
    private static let addLPMemo = "+:BTC.BTC:thor1owner"

    /// The shape every legacy `toSendTransaction(coin:vault:gas:)` produces:
    /// `SendTransaction.empty` plus recipient, amount and memo — and, before
    /// this fix, only `gas`.
    private func makeFunctionCallTransaction(
        coin: Coin,
        toAddress: String,
        amount: String,
        gas: BigInt = .zero
    ) -> SendTransaction {
        SendTransaction.empty(coin: coin, vault: .example).copy(
            toAddress: toAddress,
            amount: amount,
            memo: Self.addLPMemo,
            gas: gas,
            transactionType: .unspecified
        )
    }

    // MARK: - EVM

    /// The EVM chain-specific the SIGNING path resolves: 120,000 gas at
    /// 1.32 gwei, so `fee` = 0.0001584 ETH and `gas` = the gwei price.
    private static let signedEvmChainSpecific = BlockChainSpecific.Ethereum(
        maxFeePerGasWei: BigInt(1_320_000_000),
        priorityFeeWei: BigInt(100_000_000),
        nonce: 0,
        gasLimit: BigInt(120_000)
    )

    /// ⚠️ 120,000 gas at 1.32 gwei is 0.0001584 ETH, and that TOTAL is what an
    /// EVM fee row reads. The gas PRICE alone — the figure the old hand-off
    /// copied — is 1.32 gwei, which valued as a whole fee rounds to `$0.00`.
    func testAnEvmFunctionCallDisclosesTheTotalFee() async {
        let gasPrice = BigInt(1_320_000_000)
        let totalFee = BigInt(158_400_000_000_000)
        let pricer = FunctionTransactionFeePricer(
            interactor: MockSendInteractor(),
            fetchSigningChainSpecific: { _ in Self.signedEvmChainSpecific }
        )

        let priced = await pricer.priced(
            makeFunctionCallTransaction(coin: Self.ether, toAddress: "0xinbound", amount: "0.5")
        )

        XCTAssertEqual(
            SendCryptoLogic.displayFee(coin: priced.coin, gas: priced.gas, fee: priced.fee),
            totalFee,
            "an EVM fee row reads the total, and it must be the total that was priced"
        )
        XCTAssertEqual(priced.fee, totalFee)
        XCTAssertEqual(priced.gas, gasPrice, "the per-unit price still travels, for the balance guards")
        XCTAssertTrue(priced.gasInReadable.hasPrefix("0.0001584"), "got \(priced.gasInReadable)")
    }

    /// ⚠️ The EVM figure must come from the chain-specific the SIGNING path
    /// fetches, not from the Send flow's fee resolver.
    ///
    /// `BlockChainService.fetchSpecificForEVM` floors every transaction at the
    /// 120,000 ERC-20 gas limit; `DefaultSendInteractor.calculateEVMFee` floors
    /// a native transfer at `Coin.feeDefault` — 23,000 on Ethereum. Pricing a
    /// native ETH call through the Send resolver understates the fee by up to
    /// 5x against the limit the vault actually signs, and disagrees with the
    /// co-signer, whose `JoinKeysignGasViewModel` reads `chainSpecific.fee`
    /// straight off the payload.
    func testAnEvmFunctionCallIsPricedOffTheChainSpecificSigningUses() async {
        let mock = MockSendInteractor()
        mock.calculateEVMFeeStub = { _ in
            // The Send resolver's answer at the 23,000 native floor. If it is
            // ever consulted for an EVM function call, this is what leaks onto
            // Verify instead of the signed figure.
            SendInteractorFeeResult(fee: BigInt(30_360_000_000_000), gas: BigInt(1_320_000_000))
        }
        let pricer = FunctionTransactionFeePricer(
            interactor: mock,
            fetchSigningChainSpecific: { _ in Self.signedEvmChainSpecific }
        )

        let priced = await pricer.priced(
            makeFunctionCallTransaction(coin: Self.ether, toAddress: "0xinbound", amount: "0.5")
        )

        XCTAssertEqual(priced.fee, BigInt(158_400_000_000_000))
        XCTAssertTrue(
            mock.calculateEVMFeeCalls.isEmpty,
            "the Send resolver's 23,000-floored figure must not reach an EVM function call"
        )
    }

    /// The fee has to be priced for THIS call, not for a bare transfer: the EVM
    /// gas limit is estimated against the calldata, and the legacy screen's
    /// probe fetch carried no memo at all.
    func testAnEvmFunctionCallIsPricedAgainstItsOwnMemoAndRecipient() async {
        var fetched: [SendTransaction] = []
        let pricer = FunctionTransactionFeePricer(
            interactor: MockSendInteractor(),
            fetchSigningChainSpecific: { tx in
                fetched.append(tx)
                return Self.signedEvmChainSpecific
            }
        )

        _ = await pricer.priced(
            makeFunctionCallTransaction(coin: Self.ether, toAddress: "0xinbound", amount: "0.5")
        )

        XCTAssertEqual(fetched.first?.memo, Self.addLPMemo)
        XCTAssertEqual(fetched.first?.toAddress, "0xinbound")
    }

    // MARK: - UTXO

    /// ⚠️ A UTXO fee is `rate × size`, and the size only exists once inputs are
    /// selected — so `chainSpecific` carries a sat/vB RATE, not a fee. The old
    /// hand-off copied that rate into `gas` and left `fee` at zero, which on a
    /// chain whose fee row reads `fee` disclosed nothing at all.
    func testAUtxoFunctionCallDisclosesThePlannedFeeNotTheByteRate() async {
        let byteRate = BigInt(12)
        let plannedFee = BigInt(3_000)
        let mock = MockSendInteractor()
        mock.fetchChainSpecificStub = { _ in .UTXO(byteFee: byteRate, sendMaxAmount: false) }
        mock.calculatePlanFeeStub = { _, _ in plannedFee }

        let priced = await FunctionTransactionFeePricer(interactor: mock).priced(
            makeFunctionCallTransaction(coin: Self.bitcoin, toAddress: "bc1inbound", amount: "0.01")
        )

        XCTAssertEqual(
            SendCryptoLogic.displayFee(coin: priced.coin, gas: priced.gas, fee: priced.fee),
            plannedFee,
            "12 sat/vB is a rate; the disclosed fee is what the planned transaction pays"
        )
        XCTAssertNotEqual(priced.fee, byteRate)
        XCTAssertTrue(priced.gasInReadable.hasPrefix("0.00003"), "got \(priced.gasInReadable)")
    }

    /// The plan the fee comes from has to be the plan for this transaction.
    func testAUtxoFunctionCallIsPlannedWithItsOwnMemoAndRecipient() async {
        let mock = MockSendInteractor()
        mock.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        mock.calculatePlanFeeStub = { _, _ in BigInt(3_000) }

        _ = await FunctionTransactionFeePricer(interactor: mock).priced(
            makeFunctionCallTransaction(coin: Self.bitcoin, toAddress: "bc1inbound", amount: "0.01")
        )

        XCTAssertEqual(mock.calculatePlanFeeCalls.first?.tx.memo, Self.addLPMemo)
        XCTAssertEqual(mock.calculatePlanFeeCalls.first?.tx.toAddress, "bc1inbound")
    }

    // MARK: - Cardano

    /// The third family whose fee row reads `fee`. Cardano's `chainSpecific`
    /// also carries a rate rather than a total, and its real fee is the one the
    /// payload build derives from the signed size.
    func testACardanoFunctionCallDisclosesThePlannedFee() async {
        let plannedFee = BigInt(174_301)
        let mock = MockSendInteractor()
        mock.fetchChainSpecificStub = { _ in
            .Cardano(byteFee: BigInt(44), sendMaxAmount: false, ttl: 1_000)
        }
        mock.calculatePlanFeeStub = { _, _ in plannedFee }

        let priced = await FunctionTransactionFeePricer(interactor: mock).priced(
            makeFunctionCallTransaction(coin: Self.cardano, toAddress: "addr1inbound", amount: "5")
        )

        XCTAssertEqual(
            SendCryptoLogic.displayFee(coin: priced.coin, gas: priced.gas, fee: priced.fee),
            plannedFee
        )
        XCTAssertNotEqual(priced.fee, .zero)
    }

    // MARK: - The chains that already worked

    /// Regression guard for every DeFi builder shipping today. THORChain quotes
    /// a flat per-unit gas that IS the whole cost, its fee row reads `gas`, and
    /// pricing must not move that figure — it only fills in the `fee` the fiat
    /// strings read.
    func testAThorchainFunctionCallKeepsTheFigureItAlreadyDisclosed() async {
        let depositGas = BigInt(2_000_000)
        let mock = MockSendInteractor()
        mock.fetchChainSpecificStub = { _ in
            .THORChain(accountNumber: 0, sequence: 0, fee: 2_000_000, isDeposit: true)
        }

        let priced = await FunctionTransactionFeePricer(interactor: mock).priced(
            makeFunctionCallTransaction(coin: Self.rune, toAddress: "", amount: "1")
        )

        XCTAssertEqual(
            SendCryptoLogic.displayFee(coin: priced.coin, gas: priced.gas, fee: priced.fee),
            depositGas
        )
        XCTAssertEqual(priced.gas, depositGas)
        XCTAssertEqual(priced.fee, depositGas, "the fiat fee string reads `fee` on every chain")
    }

    // MARK: - Failure

    /// A fee endpoint that is briefly down must not strand the user, and must
    /// not invent a number either. The hand-off keeps whatever it already had —
    /// the pre-existing behaviour — and the failure is logged.
    func testAFailedPricingLeavesTheHandOffUntouched() async {
        struct Boom: Error {}
        let probeGas = BigInt(7)
        let pricer = FunctionTransactionFeePricer(
            interactor: MockSendInteractor(),
            fetchSigningChainSpecific: { _ in throw Boom() }
        )

        let priced = await pricer.priced(
            makeFunctionCallTransaction(
                coin: Self.ether, toAddress: "0xinbound", amount: "0.5", gas: probeGas
            )
        )

        XCTAssertEqual(priced.gas, probeGas)
        XCTAssertEqual(
            priced.fee,
            .zero,
            "known residual: a fetch that fails leaves the disclosure where it was, and on EVM that is zero"
        )
    }

    // MARK: - The builder pipeline

    /// The seam the Add-LP and SECURE+ migrations will land on: a builder must
    /// hand Verify a priced transaction without doing anything per-builder.
    func testAnEvmBuilderHandsVerifyAPricedTransaction() async {
        let totalFee = BigInt(158_400_000_000_000)
        let pricer = FunctionTransactionFeePricer(
            interactor: MockSendInteractor(),
            fetchSigningChainSpecific: { _ in Self.signedEvmChainSpecific }
        )
        let builder = StubFunctionTransactionBuilder(
            coin: Self.ether, toAddress: "0xinbound", amount: "0.5", memo: Self.addLPMemo
        )

        let tx = await builder.buildPricedSendTransaction(vault: .example, pricer: pricer)

        XCTAssertEqual(
            SendCryptoLogic.displayFee(coin: tx.coin, gas: tx.gas, fee: tx.fee),
            totalFee,
            "buildSendTransaction alone hardcodes fee: .zero — the pricing step is what fills it"
        )
    }

    func testAUtxoBuilderHandsVerifyAPricedTransaction() async {
        let plannedFee = BigInt(3_000)
        let mock = MockSendInteractor()
        mock.fetchChainSpecificStub = { _ in .UTXO(byteFee: BigInt(12), sendMaxAmount: false) }
        mock.calculatePlanFeeStub = { _, _ in plannedFee }
        let builder = StubFunctionTransactionBuilder(
            coin: Self.bitcoin, toAddress: "bc1inbound", amount: "0.01", memo: Self.addLPMemo
        )

        let tx = await builder.buildPricedSendTransaction(
            vault: .example, pricer: FunctionTransactionFeePricer(interactor: mock)
        )

        XCTAssertEqual(
            SendCryptoLogic.displayFee(coin: tx.coin, gas: tx.gas, fee: tx.fee),
            plannedFee
        )
    }
}

/// A minimal `TransactionBuilder` standing in for the EVM / UTXO DeFi builders
/// the migration will add. `memoFunctionDictionary` is deliberately EMPTY:
/// `SendCryptoLogic.isDeposit` is "dictionary non-empty AND not UTXO/Ripple/
/// Solana", so populating it would build an Ethereum transaction as a THORChain
/// deposit — the same trap `CancelLimitOrderTransactionBuilder` documents.
private struct StubFunctionTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let toAddress: String
    let amount: String
    let memo: String

    var sendMaxAmount: Bool { false }
    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }
}
