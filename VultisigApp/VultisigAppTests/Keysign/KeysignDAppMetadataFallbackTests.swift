//
//  KeysignDAppMetadataFallbackTests.swift
//  VultisigAppTests
//
//  The verify and done screens read the requesting dApp from the view model.
//  A transaction carries it on `KeysignPayload`; a message-signing request has
//  no `KeysignPayload` at all, so the view models fall back to the custom
//  message. Pins the precedence on both view models, and that a custom message
//  fetched from the relay by `customPayloadID` surfaces its identity too.
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class KeysignDAppMetadataFallbackTests: XCTestCase {

    private static let stubHost = "custom-message-dapp-metadata-stub.local"

    private let transactionDApp = DAppMetadata(name: "Uniswap", url: "https://app.uniswap.org", iconURL: "")
    private let messageDApp = DAppMetadata(name: "Polymarket", url: "https://polymarket.com", iconURL: "")

    /// Both view models build a `Vault` on init, which must not land in the
    /// app's real store.
    private var token: TestContextToken!

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
        RelayPayloadStubProtocol.body = nil
        URLProtocol.registerClass(RelayPayloadStubProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(RelayPayloadStubProtocol.self)
        RelayPayloadStubProtocol.body = nil
        TestStore.restore(token)
        token = nil
    }

    // MARK: - JoinKeysignViewModel

    func testJoinPrefersKeysignPayloadMetadata() {
        let viewModel = JoinKeysignViewModel()
        viewModel.keysignPayload = makeKeysignPayload(dappMetadata: transactionDApp)
        viewModel.customMessagePayload = makeCustomMessagePayload(dappMetadata: messageDApp)

        XCTAssertEqual(viewModel.dappMetadata, transactionDApp)
    }

    func testJoinFallsBackToCustomMessageMetadata() {
        let viewModel = JoinKeysignViewModel()
        viewModel.customMessagePayload = makeCustomMessagePayload(dappMetadata: messageDApp)

        XCTAssertEqual(viewModel.dappMetadata, messageDApp)
    }

    func testJoinHasNoMetadataWhenNeitherPayloadCarriesIt() {
        let viewModel = JoinKeysignViewModel()
        XCTAssertNil(viewModel.dappMetadata)

        viewModel.customMessagePayload = makeCustomMessagePayload(dappMetadata: nil)
        XCTAssertNil(viewModel.dappMetadata)
    }

    func testJoinSurfacesMetadataFromRelayFetchedCustomMessage() async throws {
        RelayPayloadStubProtocol.body = try ProtoSerializer.serialize(
            makeCustomMessagePayload(dappMetadata: messageDApp)
        )
        let viewModel = JoinKeysignViewModel()
        viewModel.serverAddress = "https://\(Self.stubHost)"
        viewModel.customPayloadID = "payload-hash"

        await viewModel.ensureCustomMessagePayload()

        XCTAssertEqual(viewModel.customMessagePayload?.method, "personal_sign")
        XCTAssertEqual(viewModel.dappMetadata, messageDApp)
        XCTAssertNotEqual(viewModel.status, .FailedToStart)
    }

    // MARK: - KeysignViewModel

    func testKeysignPrefersKeysignPayloadMetadata() {
        let viewModel = KeysignViewModel()
        viewModel.keysignPayload = makeKeysignPayload(dappMetadata: transactionDApp)
        viewModel.customMessagePayload = makeCustomMessagePayload(dappMetadata: messageDApp)

        XCTAssertEqual(viewModel.dappMetadata, transactionDApp)
    }

    func testKeysignFallsBackToCustomMessageMetadata() {
        let viewModel = KeysignViewModel()
        viewModel.customMessagePayload = makeCustomMessagePayload(dappMetadata: messageDApp)

        XCTAssertEqual(viewModel.dappMetadata, messageDApp)
    }

    func testKeysignHasNoMetadataWhenNeitherPayloadCarriesIt() {
        let viewModel = KeysignViewModel()
        XCTAssertNil(viewModel.dappMetadata)

        viewModel.customMessagePayload = makeCustomMessagePayload(dappMetadata: nil)
        XCTAssertNil(viewModel.dappMetadata)
    }

    // MARK: - Encoding

    /// The transaction encoder shares the custom-message rule: metadata that
    /// would decode to `nil` is never written as a present-but-empty message.
    func testKeysignPayloadDoesNotWriteEmptyMetadata() {
        let whitespace = DAppMetadata(name: " ", url: "", iconURL: "\n")

        XCTAssertFalse(makeKeysignPayload(dappMetadata: whitespace).mapToProtobuff().hasDappMetadata)
        XCTAssertTrue(makeKeysignPayload(dappMetadata: transactionDApp).mapToProtobuff().hasDappMetadata)
    }

    // MARK: - Helpers

    private func makeCustomMessagePayload(dappMetadata: DAppMetadata?) -> CustomMessagePayload {
        CustomMessagePayload(
            method: "personal_sign",
            message: "0x48656c6c6f",
            vaultPublicKeyECDSA: "02abc",
            vaultLocalPartyID: "party",
            chain: "Ethereum",
            dappMetadata: dappMetadata
        )
    }

    private func makeKeysignPayload(dappMetadata: DAppMetadata?) -> KeysignPayload {
        let asset = CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "logo",
            decimals: 18,
            priceProviderId: "eth",
            contractAddress: "",
            isNativeToken: true
        )
        return KeysignPayload(
            coin: Coin(asset: asset, address: "0xsender", hexPublicKey: ""),
            toAddress: "0xrecipient",
            toAmount: BigInt(1),
            chainSpecific: .Ethereum(maxFeePerGasWei: 0, priorityFeeWei: 0, nonce: 0, gasLimit: 21000),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil,
            dappMetadata: dappMetadata
        )
    }
}

/// Answers the relay's `GET /payload/{hash}` with `body`. `PayloadService`
/// builds its own `HTTPClient` over `URLSession.shared`, so a registered
/// protocol is the only seam short of changing production code.
private final class RelayPayloadStubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _body: String?

    static var body: String? {
        get { lock.lock(); defer { lock.unlock() }; return _body }
        set { lock.lock(); defer { lock.unlock() }; _body = newValue }
    }

    // These are required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "custom-message-dapp-metadata-stub.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
