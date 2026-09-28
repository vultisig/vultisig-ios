import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class WalletConnectCoordinatorRequestTests: XCTestCase {
    func testObservesSupportedMessageAndTransactionRequests() {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)

        client.requestHandler?(incoming(method: "eth_sendTransaction", requestId: "1"))
        XCTAssertEqual(coordinator.pendingMessageRequest?.requestId, .string("1"))

        client.requestHandler?(incoming(method: "personal_sign", requestId: "3"))
        XCTAssertEqual(coordinator.pendingMessageRequest?.requestId, .string("3"))
    }

    func testUnsupportedSessionRequestIsRejectedAndNotPublished() async {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)

        client.requestHandler?(incoming(method: "wallet_sendCalls", requestId: "2"))
        await waitUntil { client.rejections == ["topic:2"] }

        XCTAssertNil(coordinator.pendingMessageRequest)
        XCTAssertEqual(client.rejections, ["topic:2"])
    }

    func testSessionAuthenticateIsRejectedAndNotPublishedAsMessageRequest() async {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)

        client.authenticationHandler?(WalletConnectAuthenticationRequest(requestId: "auth-1"))
        await waitUntil { client.authenticationRejections == [.string("auth-1")] }

        XCTAssertNil(coordinator.pendingMessageRequest)
        XCTAssertEqual(client.authenticationRejections, [.string("auth-1")])
        XCTAssertTrue(client.rejections.isEmpty)
        XCTAssertTrue(client.responses.isEmpty)
    }

    func testApproveMessageRequestNormalizesAndResponds() async throws {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)
        let request = messageRequest(requestId: "10")
        let signature = String(repeating: "ab", count: 64) + "00"

        try await coordinator.approveMessageRequest(request, signature: signature)

        XCTAssertEqual(client.responses, [FakeWalletConnectPairingClient.Response(
            topic: "topic",
            requestId: "10",
            result: "0x" + String(repeating: "ab", count: 64) + "1b"
        )])
    }

    func testRejectMessageRequestUsesClientRejectAPI() async throws {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)
        let request = incoming(method: "personal_sign", requestId: "11")

        try await coordinator.rejectMessageRequest(request)

        XCTAssertEqual(client.rejections, ["topic:11"])
    }

    func testApproveMessageRequestPreservesIntegerRequestID() async throws {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)
        var request = messageRequest(requestId: "10")
        request = WalletConnectMessageRequest(
            topic: request.topic,
            requestId: .integer(10),
            method: request.method,
            chain: request.chain,
            message: request.message,
            displayMessage: request.displayMessage,
            address: request.address,
            vaultPubKeyECDSA: request.vaultPubKeyECDSA,
            vaultLocalPartyID: request.vaultLocalPartyID,
            dappMetadata: request.dappMetadata,
            verifyContext: request.verifyContext
        )

        try await coordinator.approveMessageRequest(request, signature: String(repeating: "ab", count: 64) + "00")

        XCTAssertEqual(client.responses.first?.requestId, .integer(10))
    }

    func testApproveTransactionRequestRespondsWithHashAndPreservesIntegerRequestID() async throws {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)
        let request = transactionRequest(requestId: .integer(99))

        try await coordinator.approveTransactionRequest(request, transactionHash: "0xabc123")

        XCTAssertEqual(client.responses, [FakeWalletConnectPairingClient.Response(
            topic: "topic",
            requestId: .integer(99),
            result: "0xabc123"
        )])
    }

    func testApproveTransactionRequestRejectsEmptyHash() async {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)
        let request = transactionRequest(requestId: .integer(99))

        do {
            try await coordinator.approveTransactionRequest(request, transactionHash: "")
            XCTFail("Expected empty hash to throw")
        } catch {
            XCTAssertTrue(client.responses.isEmpty)
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            await Task.yield()
        }
    }

    private func incoming(method: String, requestId: String) -> WalletConnectIncomingRequest {
        WalletConnectIncomingRequest(
            topic: "topic",
            requestId: .string(requestId),
            method: method,
            chainId: "eip155:1",
            paramsJSON: "[]",
            dappName: "Example",
            dappURL: "https://example.com",
            dappIcon: nil,
            verifyContext: nil
        )
    }

    private func transactionRequest(requestId: WalletConnectRequestID) -> WalletConnectTransactionRequest {
        let vault = Vault(name: "vault")
        vault.pubKeyECDSA = "vault-pub"
        vault.localPartyID = "local"
        let meta = CoinMeta(
            chain: .ethereum,
            ticker: Chain.ethereum.ticker,
            logo: "",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: meta, address: "0x1111111111111111111111111111111111111111", hexPublicKey: "")
        let transaction = SendTransaction.empty(coin: coin, vault: vault).copy(
            toAddress: "0x2222222222222222222222222222222222222222",
            amount: "0"
        )
        return WalletConnectTransactionRequest(
            topic: "topic",
            requestId: requestId,
            method: "eth_sendTransaction",
            chain: .ethereum,
            from: "0x1111111111111111111111111111111111111111",
            to: "0x2222222222222222222222222222222222222222",
            valueWei: .zero,
            valueAmount: "0",
            data: "",
            requestedOverrides: WalletConnectTransactionOverrides(
                gas: nil,
                gasPrice: nil,
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil,
                nonce: nil
            ),
            vaultPubKeyECDSA: "vault-pub",
            vaultLocalPartyID: "local",
            dappMetadata: DAppMetadata(name: "Example", url: "https://example.com", iconURL: ""),
            verifyContext: nil,
            transaction: transaction
        )
    }

    private func messageRequest(requestId: String) -> WalletConnectMessageRequest {
        WalletConnectMessageRequest(
            topic: "topic",
            requestId: .string(requestId),
            method: "personal_sign",
            chain: .ethereum,
            message: "hello",
            displayMessage: "hello",
            address: "0x1111111111111111111111111111111111111111",
            vaultPubKeyECDSA: "vault-pub",
            vaultLocalPartyID: "local",
            dappMetadata: DAppMetadata(name: "Example", url: "https://example.com", iconURL: ""),
            verifyContext: nil
        )
    }
}

@MainActor
private final class FakeWalletConnectPairingClient: WalletConnectPairingClient {
    struct Response: Equatable {
        let topic: String
        let requestId: WalletConnectRequestID
        let result: String
    }

    var requestHandler: (@MainActor (WalletConnectIncomingRequest) -> Void)?
    var authenticationHandler: (@MainActor (WalletConnectAuthenticationRequest) -> Void)?
    var responses: [Response] = []
    var rejections: [String] = []
    var authenticationRejections: [WalletConnectRequestID] = []

    func configure(with _: WalletConnectConfiguration) throws {}
    func pair(uri _: String) async throws { await Task.yield() }
    func observeSessionProposals(_: @escaping @MainActor (WalletConnectProposal) -> Void) {}
    func observeSessionRequests(_ handler: @escaping @MainActor (WalletConnectIncomingRequest) -> Void) {
        requestHandler = handler
    }
    func observeAuthenticationRequests(_ handler: @escaping @MainActor (WalletConnectAuthenticationRequest) -> Void) {
        authenticationHandler = handler
    }
    func approve(proposal _: WalletConnectProposal, approval _: WalletConnectEVMNamespaceApproval) async throws -> String {
        await Task.yield()
        return "topic"
    }
    func reject(proposal _: WalletConnectProposal) async throws { await Task.yield() }
    func respond(topic: String, requestId: WalletConnectRequestID, result: String) async throws {
        await Task.yield()
        responses.append(Response(topic: topic, requestId: requestId, result: result))
    }
    func rejectRequest(topic: String, requestId: WalletConnectRequestID) async throws {
        await Task.yield()
        rejections.append("\(topic):\(requestId.stringValue)")
    }
    func rejectAuthentication(_ request: WalletConnectAuthenticationRequest) async throws {
        await Task.yield()
        authenticationRejections.append(request.requestId)
    }
    func disconnect(topic _: String) async throws { await Task.yield() }
}
