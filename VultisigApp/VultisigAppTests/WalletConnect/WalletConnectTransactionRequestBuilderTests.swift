import BigInt
import XCTest
@testable import VultisigApp

final class WalletConnectTransactionRequestBuilderTests: XCTestCase {
    func testBuildsTransactionForBoundVaultMatchingAccountAndChain() throws {
        let vault = makeVault(pubKey: "bound-vault", chain: .ethereum, address: "0x1111111111111111111111111111111111111111")
        let otherVault = makeVault(pubKey: "other-vault", chain: .ethereum, address: "0x2222222222222222222222222222222222222222")
        let binding = binding(pubKey: "bound-vault")

        let request = try WalletConnectTransactionRequestBuilder().build(
            incoming: incoming(paramsJSON: transactionJSON(value: "0xde0b6b3a7640001", data: "0xa9059cbb")),
            binding: binding,
            vaults: [otherVault, vault]
        )

        XCTAssertEqual(request.vaultPubKeyECDSA, "bound-vault")
        XCTAssertEqual(request.chain, .ethereum)
        XCTAssertEqual(request.valueWei, BigInt("1000000000000000001"))
        XCTAssertEqual(request.valueAmount, "1.000000000000000001")
        XCTAssertEqual(request.transaction.memo, "0xa9059cbb")
        XCTAssertEqual(request.transaction.toAddress, "0x2222222222222222222222222222222222222222")
        XCTAssertEqual(request.dappMetadata.host, "example.com")
    }

    func testRejectsAddressMatchOnWrongChain() {
        let vault = makeVault(pubKey: "bound-vault", chain: .polygon, address: "0x1111111111111111111111111111111111111111")

        XCTAssertThrowsError(try WalletConnectTransactionRequestBuilder().build(
            incoming: incoming(paramsJSON: transactionJSON(), chainId: "eip155:1"),
            binding: binding(pubKey: "bound-vault"),
            vaults: [vault]
        )) { error in
            XCTAssertEqual(
                error as? WalletConnectTransactionRequestError,
                .missingBoundAccount("0x1111111111111111111111111111111111111111")
            )
        }
    }

    func testAcceptsGasLimitOverrideForWalletConnectTransactions() throws {
        let vault = makeVault(pubKey: "bound-vault", chain: .ethereum, address: "0x1111111111111111111111111111111111111111")

        let request = try WalletConnectTransactionRequestBuilder().build(
            incoming: incoming(paramsJSON: transactionJSON(extra: "\"gas\":\"0x5208\"")),
            binding: binding(pubKey: "bound-vault"),
            vaults: [vault]
        )

        XCTAssertEqual(request.requestedOverrides.gas, BigInt(21_000))
        XCTAssertEqual(request.transaction.estimatedGasLimit, BigInt(21_000))
        XCTAssertEqual(request.transaction.customGasLimit, BigInt(21_000))
    }

    func testAcceptsFeeAndNonceOverridesForWalletConnectTransactions() throws {
        let vault = makeVault(pubKey: "bound-vault", chain: .ethereum, address: "0x1111111111111111111111111111111111111111")

        let request = try WalletConnectTransactionRequestBuilder().build(
            incoming: incoming(paramsJSON: transactionJSON(extra: "\"gas\":\"0x5208\",\"maxFeePerGas\":\"0x64\",\"maxPriorityFeePerGas\":\"0x2\",\"nonce\":\"0x1\"")),
            binding: binding(pubKey: "bound-vault"),
            vaults: [vault]
        )

        XCTAssertEqual(request.requestedOverrides.gas, BigInt(21_000))
        XCTAssertEqual(request.requestedOverrides.maxFeePerGas, BigInt(100))
        XCTAssertEqual(request.requestedOverrides.maxPriorityFeePerGas, BigInt(2))
        XCTAssertEqual(request.requestedOverrides.nonce, BigInt(1))
    }

    func testAppliesWalletConnectOverridesToEthereumKeysignPayload() throws {
        let payload = KeysignPayload(
            coin: makeVault(pubKey: "vault", chain: .ethereum, address: "0x1111111111111111111111111111111111111111").coins[0],
            toAddress: "0x2222222222222222222222222222222222222222",
            toAmount: .zero,
            chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(10), priorityFeeWei: BigInt(1), nonce: 7, gasLimit: BigInt(21_000)),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "vault",
            vaultLocalPartyID: "local-vault",
            libType: "DKLS",
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
        let overrides = WalletConnectTransactionOverrides(
            gas: BigInt(30_000),
            gasPrice: nil,
            maxFeePerGas: BigInt(100),
            maxPriorityFeePerGas: BigInt(2),
            nonce: BigInt(1)
        )

        let updated = try payload.applyingWalletConnectOverrides(overrides)

        guard case let .Ethereum(maxFee, priorityFee, nonce, gasLimit) = updated.chainSpecific else {
            return XCTFail("Expected Ethereum chain specific")
        }
        XCTAssertEqual(maxFee, BigInt(100))
        XCTAssertEqual(priorityFee, BigInt(2))
        XCTAssertEqual(nonce, 1)
        XCTAssertEqual(gasLimit, BigInt(30_000))
    }

    func testRejectsMissingBoundVaultMissingNativeCoinAndUnsupportedChain() {
        let vault = makeVault(pubKey: "bound-vault", chain: .ethereum, address: "0x1111111111111111111111111111111111111111")
        let tokenOnlyVault = makeVault(
            pubKey: "token-only-vault",
            chain: .ethereum,
            address: "0x1111111111111111111111111111111111111111",
            isNativeToken: false
        )
        XCTAssertThrowsError(try WalletConnectTransactionRequestBuilder().build(
            incoming: incoming(paramsJSON: transactionJSON()),
            binding: nil,
            vaults: [vault]
        ))
        XCTAssertThrowsError(try WalletConnectTransactionRequestBuilder().build(
            incoming: incoming(paramsJSON: transactionJSON(), chainId: "eip155:999999"),
            binding: binding(pubKey: "bound-vault"),
            vaults: [vault]
        ))
        XCTAssertThrowsError(try WalletConnectTransactionRequestBuilder().build(
            incoming: incoming(paramsJSON: transactionJSON()),
            binding: binding(pubKey: "token-only-vault"),
            vaults: [tokenOnlyVault]
        )) { error in
            XCTAssertEqual(error as? WalletConnectTransactionRequestError, .missingNativeCoin("Ethereum"))
        }
    }

    func testVerifyContextStaysPresentationOnly() throws {
        let vault = makeVault(pubKey: "bound-vault", chain: .ethereum, address: "0x1111111111111111111111111111111111111111")
        var incoming = incoming(paramsJSON: transactionJSON())
        incoming = WalletConnectIncomingRequest(
            topic: incoming.topic,
            requestId: incoming.requestId,
            method: incoming.method,
            chainId: incoming.chainId,
            paramsJSON: incoming.paramsJSON,
            dappName: incoming.dappName,
            dappURL: incoming.dappURL,
            dappIcon: incoming.dappIcon,
            verifyContext: WalletConnectVerifyContext(origin: "https://evil.example", validation: .scam)
        )

        let request = try WalletConnectTransactionRequestBuilder().build(
            incoming: incoming,
            binding: binding(pubKey: "bound-vault"),
            vaults: [vault]
        )

        XCTAssertEqual(request.verifyContext?.validation, .scam)
        XCTAssertEqual(request.transaction.fromAddress, "0x1111111111111111111111111111111111111111")
        XCTAssertEqual(request.transaction.toAddress, "0x2222222222222222222222222222222222222222")
        XCTAssertEqual(request.transaction.amount, "0")
    }

    private func incoming(paramsJSON: String, chainId: String = "eip155:1") -> WalletConnectIncomingRequest {
        WalletConnectIncomingRequest(
            topic: "topic",
            requestId: "1",
            method: "eth_sendTransaction",
            chainId: chainId,
            paramsJSON: paramsJSON,
            dappName: "Example",
            dappURL: "https://example.com",
            dappIcon: nil,
            verifyContext: nil
        )
    }

    private func transactionJSON(
        value: String? = nil,
        data: String? = nil,
        extra: String? = nil
    ) -> String {
        var fields = [
            "\"from\":\"0x1111111111111111111111111111111111111111\"",
            "\"to\":\"0x2222222222222222222222222222222222222222\""
        ]
        if let value { fields.append("\"value\":\"\(value)\"") }
        if let data { fields.append("\"data\":\"\(data)\"") }
        if let extra { fields.append(extra) }
        return "[{\(fields.joined(separator: ","))}]"
    }

    private func binding(pubKey: String) -> WalletConnectSessionBinding {
        WalletConnectSessionBinding(
            topic: "topic",
            vaultPubKeyECDSA: pubKey,
            dappName: "Example",
            dappURL: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeVault(
        pubKey: String,
        chain: Chain,
        address: String,
        isNativeToken: Bool = true
    ) -> Vault {
        let vault = Vault(name: pubKey)
        vault.pubKeyECDSA = pubKey
        vault.localPartyID = "local-\(pubKey)"
        let meta = CoinMeta(
            chain: chain,
            ticker: chain.ticker,
            logo: "",
            decimals: 18,
            priceProviderId: "",
            contractAddress: isNativeToken ? "" : "0x3333333333333333333333333333333333333333",
            isNativeToken: isNativeToken
        )
        vault.coins = [Coin(asset: meta, address: address, hexPublicKey: "")]
        return vault
    }
}
