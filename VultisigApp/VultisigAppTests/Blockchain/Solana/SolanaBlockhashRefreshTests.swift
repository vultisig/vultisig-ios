//
//  SolanaBlockhashRefreshTests.swift
//  VultisigAppTests
//
//  `refreshSolanaBlockhash` is the last code that touches a payload before its
//  keysign messages are generated, and its general path rebuilds the payload with
//  `signData: nil`. For a payload whose whole meaning lives in `signData` that is
//  not a dropped field — the Solana signing helper then falls through to building
//  a plain transfer out of `coin` / `toAddress` / `toAmount`, so the user would
//  sign a transfer to the Kamino vault address instead of the deposit they
//  approved.
//
//  So the assertions here are about what survives, and about what the device
//  actually ends up signing.
//

import BigInt
@testable import VultisigApp
import WalletCore
import XCTest

// The fixtures build a `Vault` and a `Coin`, which are SwiftData models.
@MainActor
final class SolanaBlockhashRefreshTests: XCTestCase {

    /// A real finalized-looking blockhash, distinct from the one the fixture
    /// carries so "the fresh one" is unambiguous.
    private static let freshBlockhash = "6VjnGjZWnCyLtCd5FZTLpqm9GNjnzDrGGjyEfKNXfPKa"

    // MARK: - The bytes survive

    /// The load-bearing case. Without the branch under test this payload comes
    /// back with `signData == nil`.
    func testAKaminoPayloadKeepsItsRawTransaction() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = try Self.kaminoDepositPayload()

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)

        let signSolana = try XCTUnwrap(refreshed.signSolana, "the deposit's bytes were dropped")
        XCTAssertEqual(signSolana.rawTransactions.count, 1)
        XCTAssertNotNil(refreshed.kaminoPayload)
    }

    /// The failure this guards against, stated as a property: whatever the
    /// refresh returns must not be a payload the signing path would rebuild as a
    /// transfer. `getPreSignedImageHash` takes the raw branch only when
    /// `signSolana` is present, so its output is the proof.
    func testTheRefreshedPayloadStillSignsTheRawTransactionRatherThanATransfer() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = try Self.kaminoDepositPayload()

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)

        let messages = try SolanaHelper.getPreSignedImageHash(keysignPayload: refreshed)
        let raw = try XCTUnwrap(refreshed.signSolana?.rawTransactions.first)
        let expected = try SolanaHelper.getPreSignedImageHashForRaw(base64Transaction: raw)
        XCTAssertEqual(messages, expected)
    }

    // MARK: - The fresh blockhash is the one that gets signed

    func testTheRefreshedBlockhashIsSplicedIntoTheSignedBytes() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = try Self.kaminoDepositPayload()

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)

        let raw = try XCTUnwrap(refreshed.signSolana?.rawTransactions.first)
        let transaction = try SolanaV0Transaction(base64Transaction: raw)
        XCTAssertEqual(transaction.recentBlockhash, Self.freshBlockhash)

        // And the chain-specific record agrees, so the fee display and the bytes
        // cannot describe two different transactions.
        guard case .Solana(let recentBlockHash, _, _, _, _, _) = refreshed.chainSpecific else {
            return XCTFail("expected Solana chain specific")
        }
        XCTAssertEqual(recentBlockHash, Self.freshBlockhash)
    }

    /// The splice is an in-place 32-byte replacement, so nothing else about the
    /// transaction may move. If any account index, instruction or amount could
    /// change here, everything the validator established before signing would be
    /// worthless.
    func testNothingButTheBlockhashChanges() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = try Self.kaminoDepositPayload()

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)

        let original = try SolanaV0Transaction(
            base64Transaction: KaminoTransactionFixtures.usdcDeposit.injected
        )
        let raw = try XCTUnwrap(refreshed.signSolana?.rawTransactions.first)
        let spliced = try SolanaV0Transaction(base64Transaction: raw)

        XCTAssertEqual(spliced.wireSize, original.wireSize)
        XCTAssertEqual(spliced.staticAccountAddresses, original.staticAccountAddresses)
        XCTAssertEqual(spliced.instructions.count, original.instructions.count)
        for (index, instruction) in spliced.instructions.enumerated() {
            XCTAssertEqual(instruction.programIdIndex, original.instructions[index].programIdIndex)
            XCTAssertEqual(instruction.accountIndexes, original.instructions[index].accountIndexes)
            XCTAssertEqual(instruction.data, original.instructions[index].data)
        }
        XCTAssertEqual(
            spliced.addressTableLookups.map(\.tableAddress),
            original.addressTableLookups.map(\.tableAddress)
        )
    }

    /// The refreshed transaction still passes the validator that approved it, at
    /// the same intent. A splice that broke any of the six layers would be caught
    /// here rather than on chain.
    func testTheSplicedTransactionStillValidates() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = try Self.kaminoDepositPayload()

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)
        let raw = try XCTUnwrap(refreshed.signSolana?.rawTransactions.first)

        try KaminoTransactionValidator.validate(
            transaction: try SolanaV0Transaction(base64Transaction: raw),
            intent: Self.depositIntent,
            lookupTables: KaminoTransactionFixtures.lookupTables
        )
    }

    /// The withdraw payload travels the same branch. It has to: the marker gates
    /// the splice, and a withdraw that reached keysign without one would either
    /// carry a stale blockhash or — worse — lose its bytes and be rebuilt as a
    /// plain transfer of the withdrawn amount to the user's own address.
    func testAKaminoWithdrawPayloadIsRefreshedTheSameWay() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = try Self.kaminoWithdrawPayload()

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)

        XCTAssertEqual(refreshed.kaminoPayload?.operation, .withdraw)
        let raw = try XCTUnwrap(refreshed.signSolana?.rawTransactions.first)
        XCTAssertEqual(try SolanaV0Transaction(base64Transaction: raw).recentBlockhash, Self.freshBlockhash)

        // Still the withdraw the validator approved, at the same share amount.
        try KaminoTransactionValidator.validate(
            transaction: try SolanaV0Transaction(base64Transaction: raw),
            intent: Self.withdrawIntent,
            lookupTables: KaminoTransactionFixtures.lookupTables
        )
    }

    // MARK: - Bytes the app did not build

    /// A raw payload with no Kamino marker keeps its bytes untouched. Those 32
    /// bytes hold the nonce value in a durable-nonce transaction and are the
    /// author's to define in anything a third party supplied, so editing them is
    /// only justified where the app knows what it wrote there — but dropping them
    /// is never justified.
    func testAnUnmarkedRawPayloadKeepsItsBytesExactlyAsSupplied() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = try Self.kaminoDepositPayload(marked: false)

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)

        XCTAssertEqual(
            refreshed.signSolana?.rawTransactions,
            [KaminoTransactionFixtures.usdcDeposit.injected]
        )
        guard case .Solana(let recentBlockHash, _, _, _, _, _) = refreshed.chainSpecific else {
            return XCTFail("expected Solana chain specific")
        }
        XCTAssertEqual(recentBlockHash, Self.freshBlockhash)
    }

    // MARK: - Existing behaviour is unchanged

    /// A plain transfer carries no `signData` and is rebuilt as before.
    func testAPlainTransferStillGetsAFreshBlockhashAndNoSignData() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = Self.transferPayload()

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)

        XCTAssertNil(refreshed.signData)
        guard case .Solana(let recentBlockHash, _, _, _, _, _) = refreshed.chainSpecific else {
            return XCTFail("expected Solana chain specific")
        }
        XCTAssertEqual(recentBlockHash, Self.freshBlockhash)
    }

    /// A non-Solana payload is returned untouched, so nothing here can reach
    /// another chain's flow.
    func testANonSolanaPayloadIsUntouched() async throws {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(Self.freshBlockhash))
        let payload = KeysignPayload.example

        let refreshed = try await service.refreshSolanaBlockhash(for: payload)

        XCTAssertEqual(refreshed.coin.chain, payload.coin.chain)
        XCTAssertNil(refreshed.signData)
    }

    /// A node that cannot supply a blockhash must stop the ceremony rather than
    /// let a stale transaction through.
    func testAMissingBlockhashThrows() async {
        let service = BlockChainService(blockhashProvider: StubBlockhashProvider(nil))

        do {
            _ = try await service.refreshSolanaBlockhash(for: try Self.kaminoDepositPayload())
            XCTFail("expected a failure")
        } catch let error as BlockChainService.Errors {
            XCTAssertEqual(error, .failToGetRecentBlockHash)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

// MARK: - Fixtures

private extension SolanaBlockhashRefreshTests {

    static let owner = KaminoTransactionFixtures.usdcDeposit.feePayer
    static let depositAmount = KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 6)

    static var steakhouseVault: KaminoVaultInfo {
        KaminoVaultInfo(
            descriptor: KaminoVaultRegistry.steakhouseUSDC,
            name: KaminoVaultRegistry.steakhouseUSDC.fallbackName,
            minDeposit: KaminoTokenAmount(baseUnits: BigInt(100_000), decimals: 6),
            minWithdraw: KaminoShareAmount(baseUnits: BigInt(1_000), decimals: 6),
            lookupTable: KaminoTransactionFixtures.usdcDeposit.lookupTable,
            apy30d: 0,
            // swiftlint:disable:next force_unwrapping
            tokensPerShare: KaminoRate(apiString: "1.0536041812651029025")!,
            tokenPriceUsd: 1
        )
    }

    static var depositIntent: KaminoTransactionIntent {
        KaminoTransactionIntent(
            operation: .deposit(depositAmount),
            vault: steakhouseVault,
            owner: owner,
            priorityFee: KaminoPriorityFee(
                limit: KaminoTransactionFixtures.usdcDeposit.unitLimit,
                price: KaminoTransactionFixtures.unitPriceMicroLamports
            )
        )
    }

    /// The payload a completed deposit form produces: the mainnet-simulated
    /// injected bytes, carried as `signSolana`.
    static func kaminoDepositPayload(marked: Bool = true) throws -> KeysignPayload {
        let prepared = KaminoPreparedTransaction(
            base64: KaminoTransactionFixtures.usdcDeposit.injected,
            priorityFee: KaminoPriorityFee(
                limit: KaminoTransactionFixtures.usdcDeposit.unitLimit,
                price: KaminoTransactionFixtures.unitPriceMicroLamports
            ),
            unitsConsumed: 252_146,
            payerLamportsAfter: nil,
            recentBlockhash: try SolanaV0Transaction(
                base64Transaction: KaminoTransactionFixtures.usdcDeposit.injected
            ).recentBlockhash
        )

        let payload = try KaminoKeysignPayloadFactory.makeDeposit(
            prepared: prepared,
            vaultInfo: steakhouseVault,
            amount: depositAmount,
            coin: solanaCoin(),
            vault: testVault()
        )
        guard marked else {
            return KeysignPayload(
                coin: payload.coin,
                toAddress: payload.toAddress,
                toAmount: payload.toAmount,
                chainSpecific: payload.chainSpecific,
                utxos: payload.utxos,
                memo: payload.memo,
                swapPayload: nil,
                approvePayload: nil,
                vaultPubKeyECDSA: payload.vaultPubKeyECDSA,
                vaultLocalPartyID: payload.vaultLocalPartyID,
                libType: payload.libType,
                wasmExecuteContractPayload: nil,
                tronTransferContractPayload: nil,
                tronTriggerSmartContractPayload: nil,
                tronTransferAssetContractPayload: nil,
                qbtcClaimPayload: nil,
                isQbtcClaim: false,
                kaminoPayload: nil,
                skipBroadcast: false,
                signData: payload.signData
            )
        }
        return payload
    }

    /// The payload a completed withdraw form produces. The wire bytes are the
    /// mainnet-simulated withdraw vector, and its fee payer is a different
    /// wallet from the deposit's, so the coin has to match it.
    static func kaminoWithdrawPayload() throws -> KeysignPayload {
        let prepared = KaminoPreparedTransaction(
            base64: KaminoTransactionFixtures.usdcWithdraw.injected,
            priorityFee: KaminoPriorityFee(
                limit: KaminoTransactionFixtures.usdcWithdraw.unitLimit,
                price: KaminoTransactionFixtures.unitPriceMicroLamports
            ),
            unitsConsumed: 174_566,
            payerLamportsAfter: nil,
            recentBlockhash: try SolanaV0Transaction(
                base64Transaction: KaminoTransactionFixtures.usdcWithdraw.injected
            ).recentBlockhash
        )

        return try KaminoKeysignPayloadFactory.makeWithdraw(
            prepared: prepared,
            vaultInfo: steakhouseVault,
            shares: withdrawShares,
            tokenValue: KaminoTokenAmount(baseUnits: BigInt(5_794_822), decimals: 6),
            coin: solanaCoin(address: KaminoTransactionFixtures.usdcWithdraw.feePayer),
            vault: testVault()
        )
    }

    static let withdrawShares = KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)

    static var withdrawIntent: KaminoTransactionIntent {
        KaminoTransactionIntent(
            operation: .withdraw(
                KaminoWithdrawRequest(shares: withdrawShares, unstakedShares: withdrawShares)
            ),
            vault: steakhouseVault,
            owner: KaminoTransactionFixtures.usdcWithdraw.feePayer,
            priorityFee: KaminoPriorityFee(
                limit: KaminoTransactionFixtures.usdcWithdraw.unitLimit,
                price: KaminoTransactionFixtures.unitPriceMicroLamports
            )
        )
    }

    /// The shape the general path handles: a Solana send with no raw bytes.
    static func transferPayload() -> KeysignPayload {
        KeysignPayload(
            coin: solanaCoin(),
            toAddress: KaminoVaultRegistry.steakhouseUSDC.address,
            toAmount: BigInt(1_000),
            chainSpecific: .Solana(
                recentBlockHash: "stale",
                priorityFee: BigInt(20_000),
                priorityLimit: BigInt(320_000),
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub-ecdsa",
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

    static func solanaCoin(address: String = owner) -> Coin {
        let asset = CoinMeta(
            chain: .solana,
            ticker: "SOL",
            logo: "solana",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: asset, address: address, hexPublicKey: "0f9a6ce9f661")
        coin.rawBalance = "3000000000"
        return coin
    }

    static func testVault() -> Vault {
        Vault(
            name: "Blockhash Refresh Vault",
            signers: [],
            pubKeyECDSA: "refresh-pub-ecdsa",
            pubKeyEdDSA: "refresh-pub-eddsa",
            keyshares: [],
            localPartyID: "refresh-party",
            hexChainCode: "refresh-hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }
}

// MARK: - Test double

private struct StubBlockhashProvider: SolanaFinalizedBlockhashProviding {
    let blockhash: String?

    init(_ blockhash: String?) {
        self.blockhash = blockhash
    }

    // The protocol is async; the body is not.
    // swiftlint:disable:next async_without_await
    func fetchFinalizedBlockhash() async throws -> String? {
        blockhash
    }
}
