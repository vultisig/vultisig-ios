import XCTest
@testable import VultisigApp

@MainActor
final class WalletConnectCoordinatorRequestTests: XCTestCase {
    func testObservesOnlySupportedMessageRequests() {
        let client = FakeWalletConnectPairingClient()
        let coordinator = WalletConnectCoordinator(pairingClient: client, isConfigured: true)

        client.requestHandler?(incoming(method: "eth_sendTransaction", requestId: "1"))
        XCTAssertNil(coordinator.pendingMessageRequest)

        client.requestHandler?(incoming(method: "personal_sign", requestId: "2"))
        XCTAssertEqual(coordinator.pendingMessageRequest?.requestId, .string("2"))
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
            signature: "0x" + String(repeating: "ab", count: 64) + "1b"
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
        let signature: String
    }

    var requestHandler: (@MainActor (WalletConnectIncomingRequest) -> Void)?
    var responses: [Response] = []
    var rejections: [String] = []

    func configure(with _: WalletConnectConfiguration) throws {}
    func pair(uri _: String) async throws { await Task.yield() }
    func observeSessionProposals(_: @escaping @MainActor (WalletConnectProposal) -> Void) {}
    func observeSessionRequests(_ handler: @escaping @MainActor (WalletConnectIncomingRequest) -> Void) {
        requestHandler = { request in
            guard WalletConnectEVMNamespaceAdapter.supportedMessageMethods.contains(request.method) else { return }
            handler(request)
        }
    }
    func approve(proposal _: WalletConnectProposal, approval _: WalletConnectEVMNamespaceApproval) async throws -> String {
        await Task.yield()
        return "topic"
    }
    func reject(proposal _: WalletConnectProposal) async throws { await Task.yield() }
    func respond(topic: String, requestId: WalletConnectRequestID, signature: String) async throws {
        await Task.yield()
        responses.append(Response(topic: topic, requestId: requestId, signature: signature))
    }
    func rejectRequest(topic: String, requestId: WalletConnectRequestID) async throws {
        await Task.yield()
        rejections.append("\(topic):\(requestId.stringValue)")
    }
    func disconnect(topic _: String) async throws { await Task.yield() }
}
