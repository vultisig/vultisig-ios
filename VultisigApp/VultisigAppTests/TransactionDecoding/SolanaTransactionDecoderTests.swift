//
//  SolanaTransactionDecoderTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import WalletCore
import XCTest

/// Exercises complete-sequence matching for signed Solana instructions.
final class SolanaTransactionDecoderTests: XCTestCase {

    func testInitiatorDelegateCarriesFundingForLiveRentProjection() {
        let decoded = SolanaTransactionDecoder().decode(
            IntentContent(intent: .delegate(votePubkey: "validator", lamports: 2_100_000_000))
        )
        XCTAssertEqual(decoded?.operation, .delegate)
        XCTAssertEqual(decoded?.amount, .accountFunding(BigInt(2_100_000_000), of: .chainNative))
    }

    func testInitiatorUnstakeNamesTheWholeStakeAccount() {
        let decoded = SolanaTransactionDecoder().decode(
            IntentContent(intent: .unstake(stakeAccount: "stake-account"))
        )
        XCTAssertEqual(decoded?.operation, .unstake)
        XCTAssertEqual(decoded?.counterparty, .stakeAccount("stake-account"))
        XCTAssertEqual(decoded?.amount, .unstated)
    }

    func testInitiatorWithdrawUsesTheWithdrawingVerbAndExactAmount() {
        let decoded = SolanaTransactionDecoder().decode(
            IntentContent(intent: .withdraw(stakeAccount: "stake-account", lamports: 2_100_000_000))
        )
        XCTAssertEqual(decoded?.operation, .withdrawStake)
        XCTAssertEqual(decoded?.amount, .units(BigInt(2_100_000_000), of: .chainNative))
    }

    @MainActor
    func testInitiatorWithdrawHeroIncludesFiat() throws {
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "solana", value: 100)
        ])
        let decoded = try XCTUnwrap(
            SolanaTransactionDecoder().decode(
                IntentContent(intent: .withdraw(stakeAccount: "stake-account", lamports: 2_100_000_000))
            )
        )
        let hero = try XCTUnwrap(
            DecodedTransactionPresentation.hero(for: decoded, coin: Self.solanaCoin())
        )

        guard case .send(_, let amount) = hero else {
            return XCTFail("expected an exact withdrawal amount")
        }
        XCTAssertEqual(amount.amount, "2.1")
        XCTAssertFalse(amount.fiat?.isEmpty ?? true)
    }

    /// Accepts WalletCore's create + initialize + delegate sequence.
    func testTheAppsWalletCoreDelegateSequenceIsAccepted() throws {
        let privateKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x31, count: 32)))
        let publicKey = privateKey.getPublicKeyEd25519()
        let validatorKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x37, count: 32)))
        let validator = AnyAddress(publicKey: validatorKey.getPublicKeyEd25519(), coin: .solana).description
        let coin = Coin(
            asset: CoinMeta(
                chain: .solana, ticker: "SOL", logo: "solana", decimals: 9,
                priceProviderId: "solana", contractAddress: "", isNativeToken: true
            ),
            address: AnyAddress(publicKey: publicKey, coin: .solana).description,
            hexPublicKey: publicKey.data.hexString
        )
        let payload = KeysignPayload(
            coin: coin,
            toAddress: validator,
            toAmount: 2_000_000_000,
            chainSpecific: .Solana(
                recentBlockHash: Self.systemProgramAddress,
                priorityFee: 1_000_000,
                priorityLimit: 100_000,
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
            ),
            utxos: [], memo: nil, swapPayload: nil, approvePayload: nil,
            vaultPubKeyECDSA: "pub", vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(), wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil, tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil, qbtcClaimPayload: nil,
            isQbtcClaim: false,
            solanaStakingPayload: .delegate(votePubkey: validator, lamports: 2_000_000_000),
            skipBroadcast: false, signData: nil
        )

        let raw = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: payload)
        let reading = SolanaTransactionReader.read(base64: raw)
        XCTAssertEqual(reading?.operation, .delegate, raw)
        XCTAssertEqual(reading?.amount, .accountFunding(BigInt(2_000_000_000), of: .chainNative))
    }

    func testACompleteLinkedDelegateSequenceIsAccepted() {
        let reading = SolanaTransactionReader.read(base64: Self.delegateSequence)
        XCTAssertEqual(reading?.operation, .delegate)
        XCTAssertEqual(reading?.amount, .accountFunding(BigInt(2_100_000_000), of: .chainNative))
    }

    func testFourByteFakeCreateAccountIsRefused() {
        XCTAssertNil(SolanaTransactionReader.read(base64: Self.makeDelegateSequence(createData: Self.discriminator(0))))
    }

    func testCreateAccountOwnedByAnotherProgramIsRefused() {
        XCTAssertNil(
            SolanaTransactionReader.read(
                base64: Self.makeDelegateSequence(createData: Self.createAccountData(owner: Data(repeating: 0x99, count: 32)))
            )
        )
    }

    func testDelegateSequenceWithDifferentStakeAccountsIsRefused() {
        XCTAssertNil(SolanaTransactionReader.read(base64: Self.makeDelegateSequence(createdStakeIndex: 9)))
    }

    func testSystemTransferFollowedByInitializeAndDelegateIsRefused() {
        XCTAssertNil(SolanaTransactionReader.read(base64: Self.makeDelegateSequence(createData: Self.systemTransferData)))
    }

    /// An unrelated SOL transfer cannot hide beside a deactivate.
    func testATransferBatchedWithADeactivateIsRefused() {
        XCTAssertNil(
            SolanaTransactionReader.read(base64: Self.transferPlusDeactivate),
            "a transaction that also moves SOL elsewhere must not be named for its stake instruction alone"
        )
    }

    func testAStandaloneDeactivateIsRead() {
        let reading = SolanaTransactionReader.read(base64: Self.deactivateOnly)
        XCTAssertEqual(reading?.operation, .unstake)
        XCTAssertEqual(reading?.counterparty, .stakeAccount(Base58.encodeNoCheck(data: Self.stakeAccount)))
    }

    func testAStandaloneWithdrawUsesTheWithdrawingVerbAndExactAmount() {
        let reading = SolanaTransactionReader.read(base64: Self.withdrawOnly)
        XCTAssertEqual(reading?.operation, .withdrawStake)
        XCTAssertEqual(reading?.amount, .units(BigInt(2_100_000_000), of: .chainNative))
        XCTAssertEqual(reading?.counterparty, .stakeAccount(Base58.encodeNoCheck(data: Self.stakeAccount)))
    }

    func testDelegateProjectionSubtractsTheLiveRentReserve() async {
        let coin = Self.solanaCoin()
        let decoded = DecodedTransaction(
            operation: .delegate,
            amount: .accountFunding(BigInt(2_100_000_000), of: .chainNative),
            counterparty: .validator("validator"),
            evidence: .signedData
        )
        let reader = SolanaDelegatedAmountReader(readRentReserve: { 100_000_000 })
        let amount = await reader.amount(for: decoded, coin: coin)
        XCTAssertEqual(amount?.amount, "2")
    }

    @MainActor
    func testDelegateProjectionIncludesFiat() async throws {
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "solana", value: 100)
        ])
        let decoded = DecodedTransaction(
            operation: .delegate,
            amount: .accountFunding(BigInt(2_100_000_000), of: .chainNative),
            counterparty: .validator("validator"),
            evidence: .signedData
        )
        let reader = SolanaDelegatedAmountReader(readRentReserve: { 100_000_000 })
        let amount = await reader.amount(for: decoded, coin: Self.solanaCoin())

        XCTAssertFalse(amount?.fiat?.isEmpty ?? true)
    }

    func testUnstakeProjectionReadsOnlyTheSignedStakeAccount() async {
        let account = SolanaStakeAccount(
            pubkey: "signed-stake-account",
            lamports: 2_100_000_000,
            rentExemptReserve: 100_000_000,
            staker: "owner",
            withdrawer: "owner",
            delegation: SolanaStakeAccount.Delegation(
                votePubkey: "validator",
                activationEpoch: 1,
                deactivationEpoch: UInt64.max,
                stake: 2_000_000_000
            )
        )
        let reader = SolanaStakeAccountAmountReader(readStakeAccounts: { owner in
            XCTAssertEqual(owner, "owner")
            return [account]
        })
        let decoded = DecodedTransaction(
            operation: .unstake,
            amount: .unstated,
            counterparty: .stakeAccount("signed-stake-account"),
            evidence: .signedData
        )
        let amount = await reader.amount(for: decoded, coin: Self.solanaCoin())
        XCTAssertEqual(amount?.amount, "2")
    }

    private static func solanaCoin() -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .solana, ticker: "SOL", logo: "solana", decimals: 9,
                priceProviderId: "solana", contractAddress: "", isNativeToken: true
            ),
            address: "owner", hexPublicKey: "hex"
        )
    }

    /// A valid prefix must not hide an unparsed signed suffix.
    func testTrailingBytesAreRefused() {
        XCTAssertNil(SolanaTransactionReader.read(base64: Self.deactivateWithTrailingBytes))
    }

    // MARK: - Structured fixtures

    private static let stakeProgramAddress = "Stake11111111111111111111111111111111111111"
    private static let systemProgramAddress = "11111111111111111111111111111111"
    private static let stakeProgram = Base58.decodeNoCheck(string: stakeProgramAddress)!
    private static let systemProgram = Base58.decodeNoCheck(string: systemProgramAddress)!
    private static let payer = Data(repeating: 0x01, count: 32)
    private static let stakeAccount = Data(repeating: 0x02, count: 32)
    private static let validator = Data(repeating: 0x03, count: 32)
    private static let clock = Data(repeating: 0x04, count: 32)
    private static let history = Data(repeating: 0x05, count: 32)
    private static let config = Data(repeating: 0x06, count: 32)
    private static let rent = Data(repeating: 0x07, count: 32)
    private static let otherStakeAccount = Data(repeating: 0x08, count: 32)

    private static var deactivateOnly: String {
        message(
            accounts: [stakeProgram, stakeAccount, clock, payer],
            instructions: [(program: 0, accounts: [1, 2, 3], data: discriminator(5))]
        )
    }

    private static var withdrawOnly: String {
        message(
            accounts: [stakeProgram, stakeAccount, payer, clock, history, otherStakeAccount],
            instructions: [
                (
                    program: 0,
                    accounts: [1, 5, 2, 4, 3],
                    data: discriminator(4) + littleEndian(2_100_000_000)
                )
            ]
        )
    }

    private static var deactivateWithTrailingBytes: String {
        let base = Data(base64Encoded: deactivateOnly)! + Data([0x01, 0x02, 0x03])
        return base.base64EncodedString()
    }

    private static var delegateSequence: String {
        makeDelegateSequence()
    }

    private static func makeDelegateSequence(
        createData: Data = createAccountData(owner: stakeProgram),
        createdStakeIndex: Int = 3
    ) -> String {
        message(
            accounts: [systemProgram, stakeProgram, payer, stakeAccount, validator, clock, history, config, rent, otherStakeAccount],
            instructions: [
                (program: 0, accounts: [2, createdStakeIndex], data: createData),
                (program: 1, accounts: [3, 8], data: initializeData),
                (program: 1, accounts: [3, 4, 5, 6, 7, 2], data: discriminator(2))
            ]
        )
    }

    private static var transferPlusDeactivate: String {
        message(
            accounts: [systemProgram, stakeProgram, payer, Data(repeating: 0xAA, count: 32), stakeAccount, clock],
            instructions: [
                (program: 0, accounts: [2, 3], data: systemTransferData),
                (program: 1, accounts: [4, 5, 2], data: discriminator(5))
            ]
        )
    }

    private static var initializeData: Data {
        discriminator(0)
            + payer
            + payer
            + Data(repeating: 0, count: 8 + 8 + 32)
    }

    private static func createAccountData(owner: Data) -> Data {
        discriminator(0) + littleEndian(2_100_000_000) + littleEndian(200) + owner
    }

    private static var systemTransferData: Data {
        discriminator(2) + littleEndian(1_000_000)
    }

    private static func littleEndian(_ value: UInt64) -> Data {
        Data((0..<8).map { UInt8((value >> (UInt64($0) * 8)) & 0xFF) })
    }

    private static func discriminator(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    private static func compactU16(_ value: Int) -> Data {
        value < 0x80 ? Data([UInt8(value)]) : Data([UInt8(value & 0x7F | 0x80), UInt8(value >> 7)])
    }

    private static func message(
        accounts: [Data],
        instructions: [(program: Int, accounts: [Int], data: Data)]
    ) -> String {
        // Relayed transactions include signatures before the message.
        var out = compactU16(1) + Data(repeating: 0, count: 64)

        out += Data([1, 0, 1])                          // header
        out += compactU16(accounts.count)
        for key in accounts {
            precondition(key.count == 32)
            out += key
        }
        out += Data(repeating: 0, count: 32)            // recent blockhash
        out += compactU16(instructions.count)
        for i in instructions {
            out += Data([UInt8(i.program)])
            out += compactU16(i.accounts.count)
            out += Data(i.accounts.map(UInt8.init))
            out += compactU16(i.data.count)
            out += i.data
        }
        return out.base64EncodedString()
    }

    private struct IntentContent: SignedTransactionContent {
        let intent: SolanaStakingPayload
        var chain: Chain { .solana }
        var isNativeCoin: Bool { true }
        var rawToAddress: String { "" }
        var rawAmount: SignedAmount { .committed(.zero) }
        var signedData: SignData? { nil }
        var hasOpaqueSignedContent: Bool { true }
        var rawMemo: String? { nil }
        var rawTransactionType: VSTransactionType { .unspecified }
        var rawWasmPayload: WasmExecuteContractPayload? { nil }
        var rawSwap: SwapPayload? { nil }
        var rawApprove: ERC20ApprovePayload? { nil }
        var stakingIntent: SolanaStakingPayload? { intent }
        var cosmosStakingIntent: CosmosStakingPayload? { nil }
    }
}
