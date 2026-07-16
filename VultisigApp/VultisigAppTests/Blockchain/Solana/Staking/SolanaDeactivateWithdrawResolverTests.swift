//
//  SolanaDeactivateWithdrawResolverTests.swift
//  VultisigAppTests
//
//  Pins the deactivate (unstake) and withdraw resolver branches: each emits a
//  `SignSolana` carrying exactly one relayed raw transaction whose pre-image
//  matches the input-rebuild path (byte parity), and rejects a payload whose
//  op-type doesn't match the branch.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

private enum WithdrawPreflightTestError: Error {
    case rejected
}

private actor FakeWithdrawPreflight: SolanaWithdrawPreflightChecking {
    private(set) var encodedTransaction: String?
    private let shouldReject: Bool

    init(shouldReject: Bool = false) {
        self.shouldReject = shouldReject
    }

    // Protocol conformance requires async; this deterministic fake does no work
    // that can suspend.
    // swiftlint:disable:next async_without_await
    func validateSolanaWithdraw(encodedTransaction: String) async throws {
        self.encodedTransaction = encodedTransaction
        if shouldReject { throw WithdrawPreflightTestError.rejected }
    }
}

// Protocol conformance requires async reads; this deterministic fake never
// suspends.
// swiftlint:disable async_without_await unused_parameter
private final class RefreshingWithdrawStakingService: SolanaStakingServiceProtocol, @unchecked Sendable {
    let account: SolanaStakeAccount?

    init(account: SolanaStakeAccount?) {
        self.account = account
    }

    func fetchValidators() async throws -> [SolanaValidator] { [] }
    func fetchStakeAccounts(owner: String) async throws -> [SolanaStakeAccount] { [] }
    func fetchStakeAccount(address: String) async throws -> SolanaStakeAccount? { account }
    func fetchEpochInfo() async throws -> SolanaEpochInfo {
        SolanaEpochInfo(epoch: 1_002, slotIndex: 1, slotsInEpoch: 432_000, absoluteSlot: 1)
    }
    func fetchRentReserve() async throws -> UInt64 { 2_282_880 }
    func fetchMinDelegation() async throws -> UInt64 { 1_000_000_000 }
    func fetchInflationRate() async throws -> Double { 0.07 }
}
// swiftlint:enable async_without_await unused_parameter

final class SolanaDeactivateWithdrawResolverTests: XCTestCase {

    private let recentBlockHash = "11111111111111111111111111111111"

    private func makeSignerKey() throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: Data(hexString: "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63")!))
    }

    private func stakeAccountAddress() throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x42, count: 32)))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
    }

    private func makeCoin(privateKey: PrivateKey) -> Coin {
        let publicKey = privateKey.getPublicKeyEd25519()
        let meta = CoinMeta(
            chain: .solana, ticker: "SOL", logo: "solana", decimals: 9,
            priceProviderId: "solana", contractAddress: "", isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: AnyAddress(publicKey: publicKey, coin: .solana).description,
            hexPublicKey: publicKey.data.hexString
        )
    }

    private func makePayload(
        privateKey: PrivateKey,
        stakingPayload: SolanaStakingPayload
    ) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(privateKey: privateKey),
            toAddress: stakingPayload.stakeAccount ?? "",
            toAmount: BigInt(stakingPayload.lamports ?? 0),
            chainSpecific: .Solana(
                recentBlockHash: recentBlockHash, priorityFee: 1_000_000, priorityLimit: 100_000,
                fromAddressPubKey: nil, toAddressPubKey: nil, hasProgramId: false
            ),
            utxos: [], memo: nil, swapPayload: nil, approvePayload: nil,
            vaultPubKeyECDSA: "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b",
            vaultLocalPartyID: "localPartyID", libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil, tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil, tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil, isQbtcClaim: false,
            solanaStakingPayload: stakingPayload,
            skipBroadcast: false, signData: nil
        )
    }

    private func liveAccount(address: String, lamports: UInt64) -> SolanaStakeAccount {
        SolanaStakeAccount(
            pubkey: address,
            lamports: lamports,
            rentExemptReserve: 2_282_880,
            staker: "Owner",
            withdrawer: "Owner",
            delegation: nil
        )
    }

    // MARK: - Deactivate

    func testDeactivateEmitsSingleRelayedTransactionWithMatchingPreImage() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: stakeAccount))

        let signSolana = try SolanaStakingSignDataResolver.resolveDeactivate(basePayload: payload)

        XCTAssertEqual(signSolana.rawTransactions.count, 1)
        let relayedHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            base64Transaction: try XCTUnwrap(signSolana.rawTransactions.first)
        )
        let rebuildHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(relayedHashes, rebuildHashes)
    }

    func testDeactivateRejectsWithdrawPayload() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )

        XCTAssertThrowsError(try SolanaStakingSignDataResolver.resolveDeactivate(basePayload: payload)) { error in
            guard case SolanaStakingSignDataResolver.Errors.wrongOpType(let op) = error else {
                return XCTFail("expected wrongOpType, got \(error)")
            }
            XCTAssertEqual(op, .withdraw)
        }
    }

    // MARK: - Withdraw

    func testWithdrawEmitsSingleRelayedTransactionWithMatchingPreImage() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )

        let signSolana = try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: payload)

        XCTAssertEqual(signSolana.rawTransactions.count, 1)
        let relayedHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            base64Transaction: try XCTUnwrap(signSolana.rawTransactions.first)
        )
        let rebuildHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(relayedHashes, rebuildHashes)
    }

    func testWithdrawVerifyPreflightsExactRelayedTransaction() async throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let liveLamports: UInt64 = 1_003_200_626
        let stakingPayload = SolanaStakingPayload.withdraw(
            stakeAccount: stakeAccount,
            lamports: liveLamports
        )
        let payload = makePayload(privateKey: privateKey, stakingPayload: stakingPayload)
        let preflight = FakeWithdrawPreflight()
        let stakingService = RefreshingWithdrawStakingService(
            account: liveAccount(address: stakeAccount, lamports: liveLamports)
        )

        let signSolana = try await SolanaStakingVerifyResolver.resolve(
            payload: stakingPayload,
            basePayload: payload,
            coin: payload.coin,
            stakingService: stakingService,
            withdrawPreflight: preflight
        )

        let preflightTransaction = await preflight.encodedTransaction
        XCTAssertEqual(preflightTransaction, signSolana.rawTransactions.first)

        let expected = try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: payload)
        XCTAssertEqual(signSolana.rawTransactions, expected.rawTransactions)
    }

    func testWithdrawVerifyStopsWhenBalanceChangedAfterConfirmation() async throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let displayedLamports: UInt64 = 1_002_893_292
        let stakingPayload = SolanaStakingPayload.withdraw(
            stakeAccount: stakeAccount,
            lamports: displayedLamports
        )
        let payload = makePayload(privateKey: privateKey, stakingPayload: stakingPayload)
        let preflight = FakeWithdrawPreflight()
        let stakingService = RefreshingWithdrawStakingService(
            account: liveAccount(address: stakeAccount, lamports: 1_003_200_626)
        )

        do {
            _ = try await SolanaStakingVerifyResolver.resolve(
                payload: stakingPayload,
                basePayload: payload,
                coin: payload.coin,
                stakingService: stakingService,
                withdrawPreflight: preflight
            )
            XCTFail("expected a changed live balance to stop keysign resolution")
        } catch let error as SolanaWithdrawPreflightError {
            guard case .stakeNotReady = error else {
                return XCTFail("unexpected preflight error: \(error)")
            }
            let preflightTransaction = await preflight.encodedTransaction
            XCTAssertNil(preflightTransaction)
        } catch {
            XCTFail("expected SolanaWithdrawPreflightError.stakeNotReady, got \(error)")
        }
    }

    func testWithdrawVerifyStopsWhenStakeProgramPreflightRejectsCooldown() async throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let stakingPayload = SolanaStakingPayload.withdraw(
            stakeAccount: stakeAccount,
            lamports: 1_002_893_292
        )
        let payload = makePayload(privateKey: privateKey, stakingPayload: stakingPayload)
        let preflight = FakeWithdrawPreflight(shouldReject: true)
        let stakingService = RefreshingWithdrawStakingService(
            account: liveAccount(address: stakeAccount, lamports: 1_002_893_292)
        )

        do {
            _ = try await SolanaStakingVerifyResolver.resolve(
                payload: stakingPayload,
                basePayload: payload,
                coin: payload.coin,
                stakingService: stakingService,
                withdrawPreflight: preflight
            )
            XCTFail("expected the rejected cooldown preflight to stop verify resolution")
        } catch WithdrawPreflightTestError.rejected {
            let preflightTransaction = await preflight.encodedTransaction
            XCTAssertNotNil(preflightTransaction)
        } catch {
            XCTFail("expected WithdrawPreflightTestError.rejected, got \(error)")
        }
    }

    func testWithdrawRejectsDeactivatePayload() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: stakeAccount))

        XCTAssertThrowsError(try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: payload)) { error in
            guard case SolanaStakingSignDataResolver.Errors.wrongOpType(let op) = error else {
                return XCTFail("expected wrongOpType, got \(error)")
            }
            XCTAssertEqual(op, .unstake)
        }
    }

    func testWithdrawRejectsZeroAmount() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 0)
        )

        XCTAssertThrowsError(try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: payload)) { error in
            guard case SolanaStakingSignDataResolver.Errors.missingPayloadField(let field) = error else {
                return XCTFail("expected missingPayloadField, got \(error)")
            }
            XCTAssertEqual(field, "lamports")
        }
    }
}
