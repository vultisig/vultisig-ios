import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class NativeSwapTrackingServiceTests: XCTestCase {

    // MARK: - Source transaction first

    func testSourceStillPendingNeverAsksMidgard() async {
        for pending in [TransactionStatusResult.TransactionConfirmationStatus.pending, .notFound] {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]))
            let source = NativeSwapSourceChecker(status: pending)
            let service = NativeSwapTrackingService(httpClient: client, sourceStatus: source, storage: storage)
            await service.forceRefresh(tx: tx)
            let midgardRequests = await client.requestCount
            let sourceRequests = await source.requests
            XCTAssertEqual(sourceRequests.map { $0.chain }, [.ethereum])
            XCTAssertEqual(midgardRequests, 0)
            XCTAssertTrue(storage.statuses.isEmpty)
            XCTAssertNil(service.uiStatusByTxHash[tx.txHash])
        }
    }

    func testRevertedSourceFailsWithoutAskingMidgard() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]))
        let source = NativeSwapSourceChecker(status: .failed(reason: "execution reverted"))
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: source, storage: storage)
        await service.forceRefresh(tx: tx)
        let midgardRequests = await client.requestCount
        XCTAssertEqual(midgardRequests, 0)
        XCTAssertEqual(storage.statuses, ["failed"])
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .failed)
        XCTAssertEqual(service.failureReasonByTxHash[tx.txHash], "execution reverted")
    }

    func testUnreachableSourceIsNotAVerdict() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]))
        let source = NativeSwapSourceChecker(status: .confirmed, fails: true)
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: source, storage: storage)
        await service.forceRefresh(tx: tx)
        let midgardRequests = await client.requestCount
        XCTAssertEqual(midgardRequests, 0)
        XCTAssertTrue(storage.statuses.isEmpty)
    }

    func testConfirmedSourceThenMidgardAndSourceIsNotAskedAgain() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([]))
        let source = NativeSwapSourceChecker(status: .confirmed)
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: source, storage: storage)
        await service.forceRefresh(tx: tx)
        await client.setPayload(Self.response([Self.action()]))
        await service.forceRefresh(tx: tx)
        let sourceRequests = await source.requests
        let midgardRequests = await client.requestCount
        XCTAssertEqual(sourceRequests.count, 1)
        XCTAssertEqual(midgardRequests, 2)
        XCTAssertEqual(storage.statuses, ["completed"])
    }

    /// Their per-chain provider is Midgard itself, which reports a rate limit as
    /// `.failed`; asking it would end a healthy swap on an outage.
    func testProtocolChainSourceSkipsTheSourceProvider() async {
        for source in [Chain.thorChain, .mayaChain] {
            let tx = Self.transaction(hash: "ABCDEF", source: source, network: source)
            let storage = NativeSwapStorage(rows: [tx])
            let checker = NativeSwapSourceChecker(status: .failed(reason: "Rate limited - too many requests"))
            let service = NativeSwapTrackingService(
                httpClient: NativeSwapHTTPClient(payload: Self.response([Self.action()])),
                sourceStatus: checker,
                storage: storage
            )
            await service.forceRefresh(tx: tx)
            let sourceRequests = await checker.requests
            XCTAssertTrue(sourceRequests.isEmpty)
            XCTAssertEqual(storage.statuses, ["completed"])
        }
    }

    /// A RUNE deposit bound for Maya is recorded by THORChain's Midgard. The
    /// THORChain provider would read a rate limit as `.failed`, so that Midgard
    /// is read directly; a rejection or refund there never reaches Maya.
    func testCrossProtocolSourceIsReadFromItsOwnMidgard() async {
        let cases: [(Data, [String], [Chain])] = [
            (Self.response([Self.action(type: "failed", out: [], metadata: ["failed": ["reason": "bad memo"]])]), ["failed"], [.thorChain]),
            (Self.response([Self.action(type: "refund")]), ["refunded"], [.thorChain]),
            (Self.response([]), [], [.thorChain]),
            (Self.response([Self.action(type: "send")], count: "2"), [], [.thorChain]),
            (Self.response([Self.action(type: "send")]), ["completed"], [.thorChain, .mayaChain])
        ]
        for (thorchainMidgard, statuses, networks) in cases {
            let tx = Self.transaction(hash: "ABCDEF", source: .thorChain, network: .mayaChain)
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(
                payload: Self.response([Self.action()]),
                payloadsByNetwork: [.thorChain: thorchainMidgard]
            )
            let checker = NativeSwapSourceChecker(status: .failed(reason: "Rate limited - too many requests"))
            let service = NativeSwapTrackingService(httpClient: client, sourceStatus: checker, storage: storage)
            await service.forceRefresh(tx: tx)
            let sourceRequests = await checker.requests
            let requestedNetworks = await client.requestedNetworks
            XCTAssertTrue(sourceRequests.isEmpty)
            XCTAssertEqual(requestedNetworks, networks)
            XCTAssertEqual(storage.statuses, statuses)
        }
    }

    func testCrossProtocolSourceOutageIsNotAVerdict() async {
        let tx = Self.transaction(hash: "ABCDEF", source: .thorChain, network: .mayaChain)
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Data(), fails: true)
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        await service.forceRefresh(tx: tx)
        let requestedNetworks = await client.requestedNetworks
        XCTAssertEqual(requestedNetworks, [.thorChain])
        XCTAssertTrue(storage.statuses.isEmpty)
    }

    // MARK: - A deposit Midgard never records

    /// The node rejected the `MsgDeposit` while executing it: committed with a
    /// non-zero code, never an action. Maya answers a hash it never indexed with
    /// its unfiltered feed, so that shape must reach the node too.
    func testRejectedSameNetworkDepositFailsWithTheNodesReason() async {
        let midgardPages = [Self.response([]), Self.response([Self.action(hash: "OTHER")], count: "1446")]
        for network in [Chain.thorChain, .mayaChain] {
            for midgard in midgardPages {
                let tx = Self.transaction(hash: "ABCDEF", source: network, network: network)
                let storage = NativeSwapStorage(rows: [tx])
                let client = NativeSwapHTTPClient(
                    payload: midgard,
                    node: .committed(code: 99, rawLog: "  fail to swap: insufficient funds  ")
                )
                let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
                let result = await service.refreshForTesting(tx: tx)
                let nodeRequests = await client.nodeRequests
                XCTAssertEqual(result, .answered)
                XCTAssertEqual(nodeRequests.count, 1)
                XCTAssertEqual(storage.statuses, ["failed"])
                XCTAssertEqual(storage.errorMessages, ["fail to swap: insufficient funds"])
                XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .failed)
                XCTAssertEqual(service.failureReasonByTxHash[tx.txHash], "fail to swap: insufficient funds")
            }
        }
    }

    /// Accepted means Midgard will index it; not committed yet is not an answer.
    func testAcceptedOrUncommittedDepositKeepsWaiting() async {
        for node in [NodeStub.committed(code: 0, rawLog: ""), .noTxResponse, .notFound] {
            let tx = Self.transaction(hash: "ABCDEF", source: .thorChain, network: .thorChain)
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response([]), node: node)
            let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
            let result = await service.refreshForTesting(tx: tx)
            let nodeRequests = await client.nodeRequests
            XCTAssertEqual(result, .answered, "\(node)")
            XCTAssertEqual(nodeRequests.count, 1)
            XCTAssertTrue(storage.statuses.isEmpty)
        }
    }

    func testNodeOutageIsNotAVerdict() async {
        let tx = Self.transaction(hash: "ABCDEF", source: .thorChain, network: .thorChain)
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([]), node: .serverError)
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        let result = await service.refreshForTesting(tx: tx)
        XCTAssertEqual(result, .unavailable)
        XCTAssertTrue(storage.statuses.isEmpty)
    }

    /// The normal path costs no extra request: the node is asked only when
    /// Midgard lists nothing for a deposit made on the protocol's own chain.
    func testNodeIsAskedOnlyWhenMidgardListsNothingForAProtocolChainDeposit() async {
        let cases: [(Chain, Data, [String])] = [
            (.thorChain, Self.response([Self.action(status: "pending")]), ["swapping"]),
            (.thorChain, Self.response([Self.action(status: "unknown")]), []),
            (.ethereum, Self.response([]), [])
        ]
        for (source, midgard, statuses) in cases {
            let tx = Self.transaction(hash: "ABCDEF", source: source, network: .thorChain)
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: midgard, node: .committed(code: 99, rawLog: "rejected"))
            let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
            await service.forceRefresh(tx: tx)
            let nodeRequests = await client.nodeRequests
            XCTAssertTrue(nodeRequests.isEmpty, "\(source)")
            XCTAssertEqual(storage.statuses, statuses)
        }
    }

    func testRejectedCrossProtocolDepositFailsWithTheNodesReason() async throws {
        let thorchainNode = try XCTUnwrap(NativeSwapTrackingService.nodeTransaction(hash: "ABCDEF", chain: .thorChain))
        let tx = Self.transaction(hash: "ABCDEF", source: .thorChain, network: .mayaChain)
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([]), node: .committed(code: 5, rawLog: "invalid memo"))
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        await service.forceRefresh(tx: tx)
        let requestedNetworks = await client.requestedNetworks
        let nodeRequests = await client.nodeRequests
        XCTAssertEqual(requestedNetworks, [.thorChain])
        XCTAssertEqual(nodeRequests, [thorchainNode.baseURL.appendingPathComponent(thorchainNode.path).absoluteString])
        XCTAssertEqual(storage.statuses, ["failed"])
        XCTAssertEqual(service.failureReasonByTxHash[tx.txHash], "invalid memo")
    }

    /// Existing hosts only: the same THORChain and Maya nodes the app already
    /// talks to, per network.
    func testNodeTransactionTargetsTheProtocolNetworksNode() throws {
        let cases: [(Chain, String)] = [
            (.thorChain, ThorchainMainnetAPI.defaultLCDHost.absoluteString),
            (.thorChainChainnet, ThorchainStagenetAPI.Environment.chainnet.thornodeHost.absoluteString),
            (.thorChainStagenet, ThorchainStagenetAPI.Environment.stagenet.thornodeHost.absoluteString),
            (.mayaChain, MayaChainAPI.defaultHost.absoluteString)
        ]
        for (chain, host) in cases {
            let target = try XCTUnwrap(NativeSwapTrackingService.nodeTransaction(hash: "0xabcdef", chain: chain))
            XCTAssertEqual(target.baseURL.absoluteString, host)
            XCTAssertEqual(target.path, "/cosmos/tx/v1beta1/txs/abcdef")
            XCTAssertEqual(target.method, .get)
        }
        XCTAssertNil(NativeSwapTrackingService.nodeTransaction(hash: "abcdef", chain: .bitcoin))
    }

    func testRefreshInvalidatedDuringTheSourceCheckNeverAsksMidgard() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]))
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        var checks = 0
        await service.forceRefresh(tx: tx, shouldApply: {
            checks += 1
            return checks == 1
        })
        let midgardRequests = await client.requestCount
        XCTAssertEqual(midgardRequests, 0)
        XCTAssertTrue(storage.statuses.isEmpty)
    }

    func testPersistedMidgardAnswerMeansTheSourceAlreadyLanded() async {
        let tx = Self.transaction(latestTrackingStatus: "swapping")
        let storage = NativeSwapStorage(rows: [tx])
        let checker = NativeSwapSourceChecker(status: .pending)
        let service = NativeSwapTrackingService(
            httpClient: NativeSwapHTTPClient(payload: Self.response([Self.action()])),
            sourceStatus: checker,
            storage: storage
        )
        await service.forceRefresh(tx: tx)
        let sourceRequests = await checker.requests
        XCTAssertTrue(sourceRequests.isEmpty)
        XCTAssertEqual(storage.statuses, ["completed"])
    }

    // MARK: - Midgard outcome on the protocol network

    func testProtocolNetworkAndNormalizedInboundLookupForBTCAndEVM() async {
        for network in [Chain.thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain] {
            for source in [Chain.bitcoin, .ethereum] {
                let tx = Self.transaction(hash: source == .bitcoin ? "abcdef" : "0xaBcDeF", source: source, network: network)
                let client = NativeSwapHTTPClient(payload: Self.response([Self.action(hash: "ABCDEF")]))
                let storage = NativeSwapStorage(rows: [tx])
                let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
                await service.forceRefresh(tx: tx)
                let request = await client.lastRequest
                XCTAssertEqual(request?.hash, tx.txHash)
                XCTAssertEqual(request?.network, network)
                XCTAssertEqual(storage.statuses, ["completed"])
            }
        }
    }

    func testPendingStreamingThenCompletedWritesOnlyChanges() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([
            Self.action(status: "success"), Self.action(status: "pending")
        ]))
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        await service.forceRefresh(tx: tx)
        XCTAssertEqual(storage.statuses, ["swapping"])
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .swapping)
        await service.forceRefresh(tx: storage.rows[0])
        XCTAssertEqual(storage.statuses, ["swapping"], "an unchanged in-flight answer is not rewritten")
        await client.setPayload(Self.response([Self.action()]))
        await service.forceRefresh(tx: storage.rows[0])
        XCTAssertEqual(storage.statuses, ["swapping", "completed"])
    }

    func testRefundPartialRefundAndFailureEndTheSwapAsAnError() async {
        let cases: [([[String: Any]], String, SwapTrackingUiStatus)] = [
            ([Self.action(type: "refund")], "refunded", .refunded),
            ([Self.action(), Self.action(type: "refund")], "partially_refunded", .refunded),
            ([Self.action(type: "failed", out: [])], "failed", .failed),
            ([Self.action(type: "failed", status: "pending", out: [])], "failed", .failed),
            ([Self.action(type: "failed")], "refunded", .refunded)
        ]
        for (actions, expected, uiStatus) in cases {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response(actions))
            let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
            await service.forceRefresh(tx: tx)
            XCTAssertEqual(storage.statuses, [expected])
            XCTAssertEqual(storage.uiStatuses, [uiStatus])
            XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], uiStatus)
        }
    }

    func testPendingRefundDoesNotEndPartiallyExecutedSwap() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([
            Self.action(), Self.action(type: "refund", status: "pending")
        ]))
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        await service.forceRefresh(tx: tx)
        XCTAssertEqual(storage.statuses, ["swapping"])
    }

    func testFailedActionCarriesThorchainsReason() throws {
        let response = try Self.decode(Self.response([
            Self.action(type: "failed", out: [], metadata: ["failed": ["reason": "  swap halted  ", "code": "99"]])
        ]))
        XCTAssertEqual(
            NativeSwapTrackingService.outcome(response: response, hash: "ABCDEF"),
            NativeSwapTrackingService.MidgardOutcome(status: "failed", failureReason: "swap halted")
        )
    }

    /// Base58 is case sensitive: a signature differing only in case is another
    /// transaction, while hex case carries no meaning.
    func testInboundMatchingIsCaseSensitiveOnlyForNonHexHashes() throws {
        let signature = "2AxLNDvi5FLFHSLfgkt8duHhedTyFiiKY9EACv2J7oc7Bu3yHKM9owv7WHFaznq8YDHiXWUZQ5jEparfn3KfX4rt"
        let exact = try Self.decode(Self.response([Self.action(hash: signature)]))
        let caseVariant = try Self.decode(Self.response([Self.action(hash: signature.uppercased())]))
        XCTAssertEqual(NativeSwapTrackingService.outcome(response: exact, hash: signature)?.status, "completed")
        XCTAssertNil(NativeSwapTrackingService.outcome(response: caseVariant, hash: signature))

        let hex = try Self.decode(Self.response([Self.action(hash: "ABCDEF")]))
        XCTAssertEqual(NativeSwapTrackingService.outcome(response: hex, hash: "0xabcdef")?.status, "completed")
    }

    func testUnknownUnrelatedNonmatchingConflictingAndIncompleteResponsesAreNotVerdicts() async {
        let responses = [
            Self.response([]),
            Self.response([Self.action(type: "contract")]),
            Self.response([Self.action(hash: "OTHER")]),
            Self.response([Self.action(status: "unknown")]),
            Self.response([Self.action(status: "failed")]),
            Self.response([Self.action(), Self.action(type: "failed")]),
            Self.response([Self.action()], count: "2")
        ]
        for response in responses {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let service = NativeSwapTrackingService(
                httpClient: NativeSwapHTTPClient(payload: response),
                sourceStatus: NativeSwapSourceChecker(),
                storage: storage
            )
            await service.forceRefresh(tx: tx)
            XCTAssertTrue(storage.statuses.isEmpty)
            XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
        }
    }

    func testOutageNeverBecomesFailedAsClockAdvances() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Data(), fails: true)
        var now = Date(timeIntervalSince1970: 100)
        let service = NativeSwapTrackingService(
            httpClient: client,
            sourceStatus: NativeSwapSourceChecker(),
            storage: storage,
            clock: { now }
        )
        for _ in 0..<3 {
            await service.forceRefresh(tx: tx)
            now = now.addingTimeInterval(86_400)
        }
        let requests = await client.requestCount
        XCTAssertEqual(requests, 3)
        XCTAssertTrue(storage.statuses.isEmpty)
        XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
    }

    /// Through the real storage: the History row ends `.error` on a refund or a
    /// failure and `.successful` only on the payout, and a terminal row leaves
    /// the in-flight set the tracker resumes from.
    /// A failure also keeps the chain's reason on the row, so History still
    /// shows it after a reload; a refund stores none (History words it from the
    /// status).
    func testStoredRowEndsAsAnErrorOnRefundAndFailureAndSucceedsOnlyOnPayout() async throws {
        let failedAction = Self.action(type: "failed", out: [], metadata: ["failed": ["reason": "swap halted"]])
        let cases: [(Data, NativeSwapSourceChecker, TransactionHistoryStatus, SwapTrackingUiStatus, String?)] = [
            (Self.response([Self.action(type: "refund")]), NativeSwapSourceChecker(), .error, .refunded, nil),
            (Self.response([Self.action(), Self.action(type: "refund")]), NativeSwapSourceChecker(), .error, .refunded, nil),
            (Self.response([]), NativeSwapSourceChecker(status: .failed(reason: "reverted")), .error, .failed, "reverted"),
            (Self.response([failedAction]), NativeSwapSourceChecker(), .error, .failed, "swap halted"),
            (Self.response([Self.action()]), NativeSwapSourceChecker(), .successful, .completed, nil)
        ]
        for (payload, source, rowStatus, uiStatus, errorMessage) in cases {
            let schema = Schema([TransactionHistoryItem.self, SwapTrackingMetadata.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            let storage = TransactionHistoryStorage(modelContext: container.mainContext)
            let tx = Self.transaction()
            try storage.save(tx)
            let service = NativeSwapTrackingService(
                httpClient: NativeSwapHTTPClient(payload: payload),
                sourceStatus: source,
                storage: storage
            )
            await service.forceRefresh(tx: tx)
            let stored = try XCTUnwrap(storage.fetchTransaction(txHash: tx.txHash, pubKeyECDSA: tx.pubKeyECDSA))
            XCTAssertEqual(stored.status, rowStatus)
            XCTAssertEqual(stored.swapTrackingUiStatus, uiStatus)
            XCTAssertEqual(stored.errorMessage, errorMessage)
            XCTAssertEqual(stored.type, .swap)
            XCTAssertTrue(try storage.fetchInFlightSwapTracking(providerKind: NativeSwapTrackingService.providerKind).isEmpty)
        }
    }

    /// A terminal status ends polling, so it must not land without its reason:
    /// the failure is written only once the reason is, and retried until then.
    func testFailureWaitsForItsReasonToBeStored() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        storage.failsErrorMessageWrite = true
        let service = NativeSwapTrackingService(
            httpClient: NativeSwapHTTPClient(payload: Self.response([])),
            sourceStatus: NativeSwapSourceChecker(status: .failed(reason: "execution reverted")),
            storage: storage
        )
        await service.forceRefresh(tx: tx)
        XCTAssertTrue(storage.statuses.isEmpty)
        XCTAssertNil(service.uiStatusByTxHash[tx.txHash])

        storage.failsErrorMessageWrite = false
        await service.forceRefresh(tx: tx)
        XCTAssertEqual(storage.errorMessages, ["execution reverted"])
        XCTAssertEqual(storage.statuses, ["failed"])
    }

    /// The node's reason for a rejected deposit survives a reload of the row.
    func testNodeRejectionReasonIsStoredOnTheRow() async throws {
        let schema = Schema([TransactionHistoryItem.self, SwapTrackingMetadata.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let storage = TransactionHistoryStorage(modelContext: container.mainContext)
        let tx = Self.transaction(hash: "ABCDEF", source: .thorChain, network: .thorChain)
        try storage.save(tx)
        let service = NativeSwapTrackingService(
            httpClient: NativeSwapHTTPClient(
                payload: Self.response([]),
                node: .committed(code: 99, rawLog: " fail to swap: insufficient funds ")
            ),
            sourceStatus: NativeSwapSourceChecker(),
            storage: storage
        )
        await service.forceRefresh(tx: tx)
        let reloaded = try XCTUnwrap(storage.fetchAll(pubKeyECDSA: tx.pubKeyECDSA).first { $0.txHash == tx.txHash })
        XCTAssertEqual(reloaded.status, .error)
        XCTAssertEqual(reloaded.errorMessage, "fail to swap: insufficient funds")
        XCTAssertEqual(TransactionHistoryFailureReasonPresentation.displayText(for: reloaded), "fail to swap: insufficient funds")
    }

    // MARK: - SDK golden cases (vultisig-sdk getSwapArrivalStatus/fixtures.json)

    // The SDK fixtures omit `pools`/`date`/`height`, which Midgard always sends
    // and this app's decoder requires; they are added here and nothing else is
    // changed.

    func testSdkThorchainMidgardPendingIsInFlight() throws {
        let response = try Self.decode(Data("""
        {"count": "1", "actions": [{"status": "pending", "type": "swap", "pools": [], "date": "1", "height": "1",
          "in": [{"txID": "THOR-SOURCE"}], "out": [],
          "metadata": {"swap": {"memo": "=:BTC.BTC:bc1destination"}}}]}
        """.utf8))
        XCTAssertEqual(NativeSwapTrackingService.outcome(response: response, hash: "THOR-SOURCE")?.status, "swapping")
    }

    func testSdkThorchainMidgardRefundedIsRefunded() throws {
        let response = try Self.decode(Data("""
        {"count": "1", "actions": [{"status": "success", "type": "refund", "pools": [], "date": "1", "height": "1",
          "in": [{"txID": "THOR-REFUND-SOURCE"}], "out": [{"txID": "THOR-REFUND-OUT"}],
          "metadata": {"refund": {"reason": "emit asset less than price limit"}}}]}
        """.utf8))
        let outcome = NativeSwapTrackingService.outcome(response: response, hash: "THOR-REFUND-SOURCE")
        XCTAssertEqual(outcome?.status, "refunded")
        XCTAssertEqual(SwapKitTrackingStatusMapper.map(trackingStatus: outcome?.status), .refunded)
    }

    func testSdkMayachainMidgardSuccessIsCompleted() throws {
        let response = try Self.decode(Data("""
        {"count": "1", "actions": [{"status": "success", "type": "swap", "pools": [], "date": "1", "height": "1",
          "in": [{"txID": "MAYA-SOURCE"}], "out": [{"txID": "MAYA-DESTINATION"}],
          "metadata": {"swap": {"memo": "=:BTC.BTC:bc1destination"}}}]}
        """.utf8))
        XCTAssertEqual(NativeSwapTrackingService.outcome(response: response, hash: "MAYA-SOURCE")?.status, "completed")
    }

    /// The SDK throws here rather than report a swap error; the app's decoder
    /// rejects the page, and the tracker keeps the swap in flight.
    func testSdkMalformedSwapStatusIsNotAVerdict() async {
        let tx = Self.transaction(hash: "THOR-SOURCE")
        let storage = NativeSwapStorage(rows: [tx])
        let service = NativeSwapTrackingService(
            httpClient: NativeSwapHTTPClient(payload: Data("""
            {"count": "1", "actions": [{"type": "swap", "pools": [], "date": "1", "height": "1",
              "in": [{"txID": "THOR-SOURCE"}], "out": []}]}
            """.utf8)),
            sourceStatus: NativeSwapSourceChecker(),
            storage: storage
        )
        await service.forceRefresh(tx: tx)
        XCTAssertTrue(storage.statuses.isEmpty)
    }

    // MARK: - Lifecycle

    func testCancellationDiscardsLateSuccessAndError() async {
        for fails in [false, true] {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), fails: fails, suspended: true)
            let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
            let task = Task { await service.forceRefresh(tx: tx) }
            await client.waitUntilRequested()
            task.cancel()
            await client.release()
            await task.value
            XCTAssertTrue(storage.statuses.isEmpty)
            XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
        }
    }

    func testEligibilityInvalidationDiscardsLateResponse() async {
        for fails in [false, true] {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), fails: fails, suspended: true)
            let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
            var eligible = true
            let task = Task { await service.forceRefresh(tx: tx, shouldApply: { eligible }) }
            await client.waitUntilRequested()
            eligible = false
            await client.release()
            await task.value
            XCTAssertTrue(storage.statuses.isEmpty)
        }
    }

    func testResetInvalidatesUnregisteredOneShot() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), suspended: true)
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        let task = Task { await service.forceRefresh(tx: tx) }
        await client.waitUntilRequested()
        service.stopAllTracking()
        await client.release()
        await task.value
        XCTAssertTrue(storage.statuses.isEmpty)
        XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
    }

    func testDeletedOrReplacedRowDiscardsLateResponse() async {
        for replacement in [false, true] {
            let tx = Self.transaction()
            let storage = NativeSwapStorage(rows: [tx])
            let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), suspended: true)
            let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
            let task = Task { await service.forceRefresh(tx: tx) }
            await client.waitUntilRequested()
            storage.rows = replacement ? [Self.transaction()] : []
            await client.release()
            await task.value
            XCTAssertTrue(storage.statuses.isEmpty)
        }
    }

    func testBackgroundTerminalRemovesPausedPollerAndRejectsStaleRestart() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]))
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        service.setActive(false)
        service.start(tx: tx)
        await service.forceRefresh(tx: tx)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
        service.start(tx: tx)
        service.setActive(true)
        await service.forceRefresh(tx: tx)
        for _ in 0..<10 { await Task.yield() }
        let requests = await client.requestCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(storage.statuses, ["completed"])
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .completed)
        service.stopAllTracking()
    }

    func testPauseInvalidatesRunningPollerResponse() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]), suspended: true)
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        service.start(tx: tx)
        let pollingTask = service.pollingTaskForTesting(tx: tx)
        XCTAssertNotNil(pollingTask)
        await client.waitUntilRequested()
        service.setActive(false)
        await client.release()
        await pollingTask?.value
        XCTAssertTrue(storage.statuses.isEmpty)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)
        service.stopAllTracking()
    }

    func testSameHashInDifferentVaultsCompletesEachRecord() async {
        let first = Self.transaction(vault: "first")
        let second = Self.transaction(vault: "second")
        let storage = NativeSwapStorage(rows: [first, second])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action()]))
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        service.setActive(false)
        service.start(tx: first)
        service.start(tx: second)
        await service.forceRefresh(tx: first)
        XCTAssertEqual(service.trackedSwapCountForTesting, 1)
        await service.forceRefresh(tx: second)
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
        XCTAssertEqual(storage.statuses, ["completed", "completed"])
        XCTAssertTrue(storage.rows.isEmpty)
        service.stopAllTracking()
    }

    func testResumeUsesCompositeIdentityAndOnlySupportedProtocolMetadata() async {
        let rows = [
            Self.transaction(vault: "first"), Self.transaction(vault: "second"),
            Self.transaction(source: .bitcoin), Self.transaction(network: .ethereum),
            Self.transaction(provider: "swapKit")
        ]
        let storage = NativeSwapStorage(rows: rows)
        let service = NativeSwapTrackingService(
            httpClient: NativeSwapHTTPClient(payload: Self.response([])),
            sourceStatus: NativeSwapSourceChecker(),
            storage: storage
        )
        service.setActive(false)
        await service.resumeInFlight()
        XCTAssertEqual(service.trackedSwapCountForTesting, 3)
        service.stopAllTracking()
        XCTAssertEqual(service.trackedSwapCountForTesting, 0)
        XCTAssertTrue(service.uiStatusByTxHash.isEmpty)
    }

    func testStartDoesNotRegressAFresherCachedStatus() async {
        let tx = Self.transaction()
        let storage = NativeSwapStorage(rows: [tx])
        let client = NativeSwapHTTPClient(payload: Self.response([Self.action(status: "pending")]))
        let service = NativeSwapTrackingService(httpClient: client, sourceStatus: NativeSwapSourceChecker(), storage: storage)
        service.setActive(false)
        await service.forceRefresh(tx: tx)
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .swapping)
        service.start(tx: tx)
        XCTAssertEqual(service.uiStatusByTxHash[tx.txHash], .swapping)
        service.stopAllTracking()
    }

    func testPollIntervalNeverOutpacesTheSourceChain() {
        XCTAssertEqual(NativeSwapTrackingService.pollInterval(sourceChain: .ethereum), NativeSwapTrackingService.baseInterval)
        XCTAssertEqual(NativeSwapTrackingService.pollInterval(sourceChain: .bitcoin), 30)
        XCTAssertEqual(NativeSwapTrackingService.pollInterval(sourceChain: nil), NativeSwapTrackingService.baseInterval)
    }

    // MARK: - Fixtures

    private static func transaction(
        hash: String = "0xabcdef", vault: String = "vault", source: Chain = .ethereum,
        network: Chain = .thorChain, provider: String = NativeSwapTrackingService.providerKind,
        latestTrackingStatus: String? = nil
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(), txHash: hash, approveTxHash: nil, pubKeyECDSA: vault, type: .swap, status: .inProgress,
            chainRawValue: source.rawValue, coinTicker: "ETH", coinLogo: "eth", coinChainLogo: nil,
            amountCrypto: "1", amountFiat: "2000", fromAddress: "from", toAddress: "to",
            toCoinTicker: "BTC", toCoinLogo: "btc", toCoinChainLogo: nil, toAmountCrypto: "0.02",
            toAmountFiat: "2000", swapProvider: "THORChain", feeCrypto: "0", feeFiat: "0",
            network: source.rawValue, explorerLink: "", createdAt: Date(), completedAt: nil,
            estimatedTime: nil, errorMessage: nil,
            swapTracking: SwapTrackingMetadataData(
                providerKind: provider,
                broadcastHash: hash,
                subProvider: network.rawValue,
                latestStatus: latestTrackingStatus,
                latestTrackingStatus: latestTrackingStatus
            )
        )
    }

    private static func action(
        type: String = "swap",
        status: String = "success",
        hash: String = "ABCDEF",
        out: [[String: Any]] = [["txID": "OUTBOUND"]],
        metadata: [String: Any]? = nil
    ) -> [String: Any] {
        var action: [String: Any] = [
            "type": type, "status": status, "pools": [], "in": [["txID": hash]],
            "out": out, "date": "1", "height": "1"
        ]
        action["metadata"] = metadata
        return action
    }

    private static func response(_ actions: [[String: Any]], count: String? = nil) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: ["actions": actions, "count": count ?? String(actions.count)])
        } catch {
            XCTFail("Invalid fixture: \(error)")
            return Data()
        }
    }

    private static func decode(_ data: Data) throws -> THORChainActionsResponse {
        try JSONDecoder().decode(THORChainActionsResponse.self, from: data)
    }
}

/// What the THORChain/Maya node answers for `/cosmos/tx/v1beta1/txs/<hash>`.
private enum NodeStub {
    case committed(code: Int, rawLog: String?)
    case noTxResponse
    case notFound
    case serverError
}

private actor NativeSwapHTTPClient: HTTPClientProtocol {
    private var payload: Data
    private let payloadsByNetwork: [Chain: Data]
    private let node: NodeStub
    private let fails: Bool
    private let suspended: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0
    private(set) var lastRequest: (hash: String, network: Chain)?
    private(set) var requestedNetworks: [Chain] = []
    private(set) var nodeRequests: [String] = []

    init(
        payload: Data,
        payloadsByNetwork: [Chain: Data] = [:],
        node: NodeStub = .notFound,
        fails: Bool = false,
        suspended: Bool = false
    ) {
        self.payload = payload
        self.payloadsByNetwork = payloadsByNetwork
        self.node = node
        self.fails = fails
        self.suspended = suspended
    }

    func setPayload(_ payload: Data) { self.payload = payload }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        var body = payload
        if let api = target as? THORChainTransactionStatusAPI, case let .getActions(hash, chain) = api {
            lastRequest = (hash, chain)
            requestedNetworks.append(chain)
            body = payloadsByNetwork[chain] ?? payload
        } else {
            nodeRequests.append(target.baseURL.appendingPathComponent(target.path).absoluteString)
            switch node {
            case let .committed(code, rawLog):
                var result: [String: Any] = ["code": code, "height": "1"]
                result["raw_log"] = rawLog
                body = try JSONSerialization.data(withJSONObject: ["tx_response": result])
            case .noTxResponse:
                body = Data("{}".utf8)
            case .notFound:
                throw HTTPError.statusCode(404, nil)
            case .serverError:
                throw HTTPError.statusCode(503, nil)
            }
        }
        requestCount += 1
        for observer in observers { observer.resume() }
        observers.removeAll()
        if suspended { await withCheckedContinuation { continuation = $0 } }
        if fails { throw URLError(.notConnectedToInternet) }
        return HTTPResponse(data: body, response: HTTPURLResponse(
            url: URL(string: "https://native-swap.invalid")!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!)
    }

    func waitUntilRequested() async {
        if requestCount == 0 { await withCheckedContinuation { observers.append($0) } }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor NativeSwapSourceChecker: TransactionStatusChecking {
    private let status: TransactionStatusResult.TransactionConfirmationStatus
    private let fails: Bool
    private(set) var requests: [(hash: String, chain: Chain)] = []

    init(status: TransactionStatusResult.TransactionConfirmationStatus = .confirmed, fails: Bool = false) {
        self.status = status
        self.fails = fails
    }

    func checkTransactionStatus(txHash: String, chain: Chain) throws -> TransactionStatusResult {
        requests.append((txHash, chain))
        if fails { throw URLError(.timedOut) }
        return TransactionStatusResult(status: status, blockNumber: nil, confirmations: nil)
    }
}

@MainActor
private final class NativeSwapStorage: NativeSwapTrackingStorage {
    var rows: [TransactionHistoryData]
    var statuses: [String] = []
    var errorMessages: [String] = []
    var uiStatuses: [SwapTrackingUiStatus] = []
    var failsErrorMessageWrite = false

    init(rows: [TransactionHistoryData]) { self.rows = rows }

    func fetchInFlightSwapTracking(providerKind: String) throws -> [TransactionHistoryData] {
        rows.filter { $0.swapTracking?.providerKind == providerKind && !$0.swapTrackingUiStatus.isTerminal }
    }

    func updateSwapTrackingStatus(
        txHash: String, pubKeyECDSA: String, latestStatus _: String?, latestTrackingStatus: String?,
        uiStatus: SwapTrackingUiStatus, polledAt _: Date
    ) throws {
        statuses.append(latestTrackingStatus ?? "")
        uiStatuses.append(uiStatus)
        if uiStatus.isTerminal {
            rows.removeAll { $0.txHash == txHash && $0.pubKeyECDSA == pubKeyECDSA }
            return
        }
        rows = rows.map { row in
            guard row.txHash == txHash, row.pubKeyECDSA == pubKeyECDSA, let tracking = row.swapTracking else { return row }
            return row.replacingTracking(SwapTrackingMetadataData(
                providerKind: tracking.providerKind,
                broadcastHash: tracking.broadcastHash,
                subProvider: tracking.subProvider,
                latestStatus: latestTrackingStatus,
                latestTrackingStatus: latestTrackingStatus
            ))
        }
    }

    func touchSwapTrackingLastPolled(txHash _: String, pubKeyECDSA _: String, polledAt _: Date) throws {}

    func updateErrorMessage(txHash _: String, pubKeyECDSA _: String, errorMessage: String) throws {
        if failsErrorMessageWrite { throw URLError(.cannotWriteToFile) }
        errorMessages.append(errorMessage)
    }
}

private extension TransactionHistoryData {
    func replacingTracking(_ tracking: SwapTrackingMetadataData) -> TransactionHistoryData {
        TransactionHistoryData(
            id: id, txHash: txHash, approveTxHash: approveTxHash, pubKeyECDSA: pubKeyECDSA, type: type, status: status,
            chainRawValue: chainRawValue, coinTicker: coinTicker, coinLogo: coinLogo, coinChainLogo: coinChainLogo,
            amountCrypto: amountCrypto, amountFiat: amountFiat, fromAddress: fromAddress, toAddress: toAddress,
            toCoinTicker: toCoinTicker, toCoinLogo: toCoinLogo, toCoinChainLogo: toCoinChainLogo,
            toAmountCrypto: toAmountCrypto, toAmountFiat: toAmountFiat, swapProvider: swapProvider,
            feeCrypto: feeCrypto, feeFiat: feeFiat, network: network, explorerLink: explorerLink,
            createdAt: createdAt, completedAt: completedAt, estimatedTime: estimatedTime,
            errorMessage: errorMessage, swapTracking: tracking
        )
    }
}
