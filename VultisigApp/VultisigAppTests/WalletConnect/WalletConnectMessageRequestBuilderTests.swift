import XCTest
@testable import VultisigApp

final class WalletConnectMessageRequestBuilderTests: XCTestCase {
    func testBuildsPayloadForBoundVaultAndMatchingAccountOnly() throws {
        let vault = makeVault(pubKey: "bound-vault", address: "0x1111111111111111111111111111111111111111")
        let otherVault = makeVault(pubKey: "other-vault", address: "0x2222222222222222222222222222222222222222")
        let binding = WalletConnectSessionBinding(
            topic: "topic",
            vaultPubKeyECDSA: "bound-vault",
            dappName: "Example",
            dappURL: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let request = try WalletConnectMessageRequestBuilder().build(
            incoming: incoming(address: "0x1111111111111111111111111111111111111111"),
            binding: binding,
            vaults: [otherVault, vault]
        )

        XCTAssertEqual(request.vaultPubKeyECDSA, "bound-vault")
        XCTAssertEqual(request.chain, .ethereum)
        XCTAssertEqual(request.customMessagePayload.dappMetadata?.host, "example.com")
    }

    func testRejectsWhenBoundVaultDoesNotHaveRequestedAccount() {
        let vault = makeVault(pubKey: "bound-vault", address: "0x1111111111111111111111111111111111111111")
        let binding = WalletConnectSessionBinding(
            topic: "topic",
            vaultPubKeyECDSA: "bound-vault",
            dappName: "Example",
            dappURL: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertThrowsError(try WalletConnectMessageRequestBuilder().build(
            incoming: incoming(address: "0x2222222222222222222222222222222222222222"),
            binding: binding,
            vaults: [vault]
        )) { error in
            XCTAssertEqual(
                error as? WalletConnectMessageRequestError,
                .missingBoundAccount("0x2222222222222222222222222222222222222222")
            )
        }
    }

    private func incoming(address: String) -> WalletConnectIncomingRequest {
        WalletConnectIncomingRequest(
            topic: "topic",
            requestId: "1",
            method: "personal_sign",
            chainId: "eip155:1",
            paramsJSON: "[\"hello\",\"\(address)\"]",
            dappName: "Example",
            dappURL: "https://example.com",
            dappIcon: nil,
            verifyContext: nil
        )
    }

    private func makeVault(pubKey: String, address: String) -> Vault {
        let vault = Vault(name: pubKey)
        vault.pubKeyECDSA = pubKey
        vault.localPartyID = "local-\(pubKey)"
        let meta = CoinMeta(
            chain: .ethereum,
            ticker: Chain.ethereum.ticker,
            logo: "",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        vault.coins = [Coin(asset: meta, address: address, hexPublicKey: "")]
        return vault
    }
}
