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

        let (swapPayload, approvePayload) = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(tx: tx, approvalDecision: nil)

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

        let (swapPayload, approvePayload) = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(tx: tx, approvalDecision: nil)

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
        let pricer = FunctionTransactionFeePricer(
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
        ).buildPricedSendTransaction(vault: .example, pricer: FunctionTransactionFeePricer(interactor: mock))

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
        let pricer = FunctionTransactionFeePricer(
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

    // MARK: - MayaChain

    /// Only a MayaChain deposit carries the protocol marker, so the THORChain
    /// dictionary stays exactly what it was.
    func testOnlyAMayaDepositMarksItsProtocol() {
        var maya = builder(
            coin: AddLPFixture.bitcoin(),
            amount: "0.5",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.mayaAddress,
            toAddress: AddLPFixture.mayaBtcVault
        )
        maya.protocolChain = .mayaChain
        let thor = builder(
            coin: AddLPFixture.bitcoin(),
            amount: "0.5",
            pool: AddLPFixture.btcPool,
            pairedAddress: AddLPFixture.thorAddress,
            toAddress: AddLPFixture.btcVault
        )

        XCTAssertEqual(maya.memoFunctionDictionary.get("protocol"), AddLPTransactionBuilder.mayaProtocolMarker)
        XCTAssertNil(thor.memoFunctionDictionary.get("protocol"))
    }

    /// ⚠️ The router call carries the inbound VAULT as an argument. A MayaChain
    /// ERC-20 deposit must name Maya's vault there — THORChain's would strand
    /// the tokens — and must be signed as a Maya payload.
    func testAMayaErc20DepositIsBuiltAgainstTheMayaInboundVault() async throws {
        var deposit = builder(
            coin: AddLPFixture.usdc(),
            amount: "10",
            pool: AddLPFixture.usdcPool,
            pairedAddress: AddLPFixture.mayaAddress,
            toAddress: AddLPFixture.mayaEthRouter
        )
        deposit.protocolChain = .mayaChain
        let tx = deposit.buildSendTransaction(vault: .example)
        let decision = ERC20ApprovalDecision(
            query: try XCTUnwrap(ThorchainRouterDepositBuilder.approvalQuery(for: tx)),
            requirement: .notRequired
        )

        let (swapPayload, _) = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(
            tx: tx,
            approvalDecision: decision,
            thorchainService: ThorchainService(httpClient: LPInboundStubClient(
                path: "/thorchain/inbound_addresses",
                address: AddLPFixture.ethVault,
                router: AddLPFixture.ethRouter
            )),
            mayachainService: MayachainService(httpClient: LPInboundStubClient(
                path: "/mayachain/inbound_addresses",
                address: AddLPFixture.mayaEthVault,
                router: AddLPFixture.mayaEthRouter,
                pool: AddLPFixture.usdcPool
            ))
        )

        guard case .mayachain(let payload) = try XCTUnwrap(swapPayload) else {
            return XCTFail("a MayaChain deposit must be signed as a Maya payload")
        }
        XCTAssertEqual(payload.vaultAddress, AddLPFixture.mayaEthVault)
        XCTAssertEqual(payload.routerAddress, AddLPFixture.mayaEthRouter)
    }

    /// The router the deposit was built against must still be Maya's router
    /// when it is signed; a rotated one is refused rather than paired with the
    /// current vault.
    func testAMayaErc20DepositIsRefusedWhenTheRouterRotated() async throws {
        var deposit = builder(
            coin: AddLPFixture.usdc(),
            amount: "10",
            pool: AddLPFixture.usdcPool,
            pairedAddress: AddLPFixture.mayaAddress,
            toAddress: "0xretiredrouter"
        )
        deposit.protocolChain = .mayaChain
        let tx = deposit.buildSendTransaction(vault: .example)
        let decision = ERC20ApprovalDecision(
            query: try XCTUnwrap(ThorchainRouterDepositBuilder.approvalQuery(for: tx)),
            requirement: .notRequired
        )

        do {
            _ = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(
                tx: tx,
                approvalDecision: decision,
                mayachainService: MayachainService(httpClient: LPInboundStubClient(
                    path: "/mayachain/inbound_addresses",
                    address: AddLPFixture.mayaEthVault,
                    router: AddLPFixture.mayaEthRouter,
                    pool: AddLPFixture.usdcPool
                ))
            )
            XCTFail("a rotated router must not be signed")
        } catch is HelperError {
        }
    }

    /// The pool the memo names must still take adds when the router deposit is
    /// built: a clear inbound halt flag says nothing about a pool that has left
    /// the list or been suspended since the form opened.
    func testAMayaErc20DepositIsRefusedWhenItsPoolIsNoLongerOffered() async throws {
        for (pool, status) in [(AddLPFixture.ethPool, "Available"), (AddLPFixture.usdcPool, "Suspended")] {
            var deposit = builder(
                coin: AddLPFixture.usdc(),
                amount: "10",
                pool: AddLPFixture.usdcPool,
                pairedAddress: AddLPFixture.mayaAddress,
                toAddress: AddLPFixture.mayaEthRouter
            )
            deposit.protocolChain = .mayaChain
            let tx = deposit.buildSendTransaction(vault: .example)
            let decision = ERC20ApprovalDecision(
                query: try XCTUnwrap(ThorchainRouterDepositBuilder.approvalQuery(for: tx)),
                requirement: .notRequired
            )

            do {
                _ = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(
                    tx: tx,
                    approvalDecision: decision,
                    mayachainService: MayachainService(httpClient: LPInboundStubClient(
                        path: "/mayachain/inbound_addresses",
                        address: AddLPFixture.mayaEthVault,
                        router: AddLPFixture.mayaEthRouter,
                        pool: pool,
                        poolStatus: status
                    ))
                )
                XCTFail("\(pool) \(status): an ineligible pool must not be deposited into")
            } catch let error as HelperError {
                XCTAssertEqual(error.localizedDescription, "addLpDestinationUnavailable".localized)
            }
        }
    }

    /// A MayaChain deposit whose chain has no inbound entry must say MayaChain
    /// does not support it, not borrow THORChain's wording.
    func testAMayaErc20DepositWithNoInboundNamesMayaChain() async throws {
        var deposit = builder(
            coin: AddLPFixture.usdc(),
            amount: "10",
            pool: AddLPFixture.usdcPool,
            pairedAddress: AddLPFixture.mayaAddress,
            toAddress: AddLPFixture.mayaEthRouter
        )
        deposit.protocolChain = .mayaChain
        let tx = deposit.buildSendTransaction(vault: .example)
        let decision = ERC20ApprovalDecision(
            query: try XCTUnwrap(ThorchainRouterDepositBuilder.approvalQuery(for: tx)),
            requirement: .notRequired
        )

        do {
            _ = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(
                tx: tx,
                approvalDecision: decision,
                mayachainService: MayachainService(httpClient: LPInboundStubClient(
                    path: "/mayachain/inbound_addresses",
                    address: AddLPFixture.mayaEthVault,
                    router: AddLPFixture.mayaEthRouter,
                    chain: "BTC"
                ))
            )
            XCTFail("a chain without a Maya inbound must not be deposited")
        } catch let error as HelperError {
            let expected = String(format: "mayaInboundAddressNotFound".localized, "ETH")
            XCTAssertEqual(error.localizedDescription, expected)
        }
    }

    /// Maya's pool list names its CACAO side `balance_cacao`; it must still
    /// decode into the shared pool model, status included.
    func testMayaPoolsDecodeIntoThePoolModel() throws {
        let json = """
        [{"balance_cacao":"829279815415031","balance_asset":"3632195306916","asset":"BTC.BTC",
          "LP_units":"1","pool_units":"1","status":"Available","decimals":8,
          "synth_units":"0","synth_supply":"0","pending_inbound_cacao":"5","pending_inbound_asset":"0"},
         {"asset":"ARB.ETH","status":"Staged","balance_cacao":"1","balance_asset":"2",
          "LP_units":"1","pool_units":"1","synth_units":"0","synth_supply":"0",
          "pending_inbound_cacao":"0","pending_inbound_asset":"0"}]
        """
        let pools = try JSONDecoder().decode([MayaChainPool].self, from: Data(json.utf8)).map(\.pool)

        XCTAssertEqual(pools.map(\.asset), ["BTC.BTC", "ARB.ETH"])
        XCTAssertEqual(pools.first?.balanceRune, "829279815415031")
        XCTAssertEqual(pools.first?.pendingInboundRune, "5")
        XCTAssertTrue(pools[0].supportsPairedLPAdd)
        XCTAssertTrue(pools[1].isStaged)
    }
}

/// Serves one inbound-address row on `path`, optionally Maya's pool list, and
/// 501s anything else.
private actor LPInboundStubClient: HTTPClientProtocol {
    private let path: String
    private let body: Data
    private let pools: Data?

    /// `pool`/`poolStatus` serve a one-pool `/mayachain/pools` answer.
    init(
        path: String,
        address: String,
        router: String,
        chain: String = "ETH",
        pool: String? = nil,
        poolStatus: String = "Available"
    ) {
        self.path = path
        self.body = Data("""
        [{"chain":"\(chain)","address":"\(address)","router":"\(router)","halted":false,
          "gas_rate":"1","gas_rate_units":"gwei"}]
        """.utf8)
        self.pools = pool.map { pool in
            Data("""
            [{"asset":"\(pool)","status":"\(poolStatus)","balance_cacao":"1","balance_asset":"1","pool_units":"1",
              "LP_units":"1","synth_units":"0","synth_supply":"0",
              "pending_inbound_cacao":"0","pending_inbound_asset":"0"}]
            """.utf8)
        }
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        let payload: Data
        if target.path == path {
            payload = body
        } else if target.path == "/mayachain/pools", let pools {
            payload = pools
        } else {
            throw HTTPError.statusCode(501, nil)
        }
        let url = target.baseURL.appendingPathComponent(target.path)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw HTTPError.invalidResponse
        }
        return HTTPResponse(data: payload, response: response)
    }
}
