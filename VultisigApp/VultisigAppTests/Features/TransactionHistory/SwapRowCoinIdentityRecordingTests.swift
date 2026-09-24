//
//  SwapRowCoinIdentityRecordingTests.swift
//  VultisigAppTests
//
//  A swap row has to name its coins precisely enough to reopen the swap form
//  on the same pair: a ticker alone cannot tell Ethereum USDC from Arbitrum
//  USDC, or a curated token from a custom one with the same ticker. Both
//  devices record the row, so both paths are pinned — through a real
//  SwiftData round trip, since the fields are only useful if they survive it.
//

import BigInt
import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class SwapRowCoinIdentityRecordingTests: XCTestCase {

    private static let usdcContract = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    private static let vaultPubKey = "swap-identity-vault"

    private var container: ModelContainer!
    private var storage: TransactionHistoryStorage!
    private var recorder: TransactionHistoryRecorder!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([TransactionHistoryItem.self, SwapTrackingMetadata.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        storage = TransactionHistoryStorage(modelContext: container.mainContext)
        recorder = TransactionHistoryRecorder(storage: storage)
    }

    override func tearDown() async throws {
        recorder = nil
        storage = nil
        container = nil
        try await super.tearDown()
    }

    /// The initiator records through `recordSwap` with the coins of the
    /// transaction it staged.
    func testInitiatorSwapRowStoresBothCoinsIdentity() throws {
        recorder.recordSwap(
            txHash: "0xinitiator",
            approveTxHash: nil,
            pubKeyECDSA: Self.vaultPubKey,
            fromCoin: makeUSDC(),
            toCoin: makeBTC(),
            fromAmountCrypto: "100 USDC",
            fromAmountFiat: "100",
            toAmountCrypto: "0.001 BTC",
            toAmountFiat: "100",
            fromAddress: "0xvault",
            toAddress: "bc1qvault",
            feeCrypto: "",
            feeFiat: "",
            chain: .ethereum,
            explorerLink: "",
            provider: "THORChain"
        )

        let row = try XCTUnwrap(storage.fetchAll(pubKeyECDSA: Self.vaultPubKey).first)
        XCTAssertEqual(row.type, .swap)
        XCTAssertEqual(row.fromContractAddress, Self.usdcContract)
        XCTAssertEqual(row.toChainRawValue, Chain.bitcoin.rawValue)
        XCTAssertEqual(row.toContractAddress, "", "a native destination has no contract")
    }

    /// The co-signer has only the signed payload; its swap payload carries the
    /// same two coins, and the row must name them the same way.
    func testCosignerSwapRowStoresBothCoinsIdentity() throws {
        let vault = Vault(
            name: "Co-signer",
            signers: [],
            pubKeyECDSA: Self.vaultPubKey,
            pubKeyEdDSA: "swap-identity-eddsa",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "",
            resharePrefix: nil,
            libType: .DKLS
        )

        recorder.recordFromKeysignPayload(
            txHash: "0xcosigner",
            approveTxHash: nil,
            vault: vault,
            keysignPayload: makeSwapPayload(fromCoin: makeUSDC(), toCoin: makeBTC())
        )

        let row = try XCTUnwrap(storage.fetchAll(pubKeyECDSA: Self.vaultPubKey).first)
        XCTAssertEqual(row.type, .swap)
        XCTAssertEqual(row.fromContractAddress, Self.usdcContract)
        XCTAssertEqual(row.toChainRawValue, Chain.bitcoin.rawValue)
        XCTAssertEqual(row.toContractAddress, "")
    }

    /// A row written before these fields existed reads back with them absent,
    /// not empty: an absent destination chain is what tells the resolver to
    /// fall back to the legacy match.
    func testLegacyRowReadsBackWithoutCoinIdentity() throws {
        let item = TransactionHistoryItem(
            txHash: "0xlegacy",
            pubKeyECDSA: Self.vaultPubKey,
            typeRawValue: TransactionHistoryType.swap.rawValue,
            statusRawValue: TransactionHistoryStatus.error.rawValue,
            chainRawValue: Chain.ethereum.rawValue,
            coinTicker: "USDC",
            coinLogo: "usdc",
            amountCrypto: "100 USDC",
            amountFiat: "100",
            fromAddress: "0xvault",
            toAddress: "bc1qvault",
            toCoinTicker: "BTC",
            feeCrypto: "",
            feeFiat: "",
            network: "Ethereum",
            explorerLink: ""
        )
        container.mainContext.insert(item)
        try container.mainContext.save()

        let row = try XCTUnwrap(storage.fetchAll(pubKeyECDSA: Self.vaultPubKey).first)
        XCTAssertNil(row.fromContractAddress)
        XCTAssertNil(row.toChainRawValue)
        XCTAssertNil(row.toContractAddress)
    }

    // MARK: - Fixtures

    private func makeUSDC() -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .ethereum,
                ticker: "USDC",
                logo: "usdc",
                decimals: 6,
                priceProviderId: "",
                contractAddress: Self.usdcContract,
                isNativeToken: false
            ),
            address: "0xvault",
            hexPublicKey: ""
        )
    }

    private func makeBTC() -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .bitcoin,
                ticker: "BTC",
                logo: "btc",
                decimals: 8,
                priceProviderId: "",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "bc1qvault",
            hexPublicKey: ""
        )
    }

    private func makeSwapPayload(fromCoin: Coin, toCoin: Coin) -> KeysignPayload {
        KeysignPayload(
            coin: fromCoin,
            toAddress: "0xrouter",
            toAmount: BigInt(100_000_000),
            chainSpecific: .Ethereum(
                maxFeePerGasWei: BigInt(1),
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: BigInt(21_000)
            ),
            utxos: [],
            memo: nil,
            swapPayload: .thorchain(
                THORChainSwapPayload(
                    fromAddress: fromCoin.address,
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    vaultAddress: "0xinbound",
                    routerAddress: "0xrouter",
                    fromAmount: BigInt(100_000_000),
                    toAmountDecimal: 0.001,
                    toAmountLimit: "0",
                    streamingInterval: "0",
                    streamingQuantity: "0",
                    expirationTime: 0,
                    isAffiliate: false
                )
            ),
            approvePayload: nil,
            vaultPubKeyECDSA: Self.vaultPubKey,
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }
}
