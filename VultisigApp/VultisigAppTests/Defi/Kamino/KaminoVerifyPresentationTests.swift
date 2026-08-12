//
//  KaminoVerifyPresentationTests.swift
//  VultisigAppTests
//
//  A Kamino transaction is built by Kamino and signed verbatim, and the marker
//  that records what the app asked for is local to the initiating device. So a
//  co-signer's whole basis for approving one is this decode. What follows is
//  mostly the same shape as the validator suite: take bytes that are known to
//  execute on mainnet, change exactly one thing, and assert the reading changes
//  or the decode refuses.
//

import BigInt
@testable import VultisigApp
import WalletCore
import XCTest

final class KaminoVerifyPresentationTests: XCTestCase {

    // MARK: - Decoding the golden vectors

    /// The three captured transactions read back as what they are. Every field
    /// here comes from the bytes plus the registry — no payload, no API.
    func testDecodesTheUsdcDeposit() throws {
        let decoded = try decode(KaminoTransactionFixtures.usdcDeposit.source)

        XCTAssertEqual(decoded.operation, .deposit)
        XCTAssertEqual(decoded.descriptor, KaminoVaultRegistry.steakhouseUSDC)
        XCTAssertEqual(decoded.amountBaseUnits, BigInt(10_000_000))
        XCTAssertEqual(decoded.amountDecimals, 6)
        XCTAssertEqual(decoded.amountString, "10")
        XCTAssertEqual(decoded.signer, KaminoTransactionFixtures.usdcDeposit.feePayer)
        XCTAssertFalse(decoded.strandsWrappedSolRent)
    }

    func testDecodesTheSolDeposit() throws {
        let decoded = try decode(KaminoTransactionFixtures.solDeposit.source)

        XCTAssertEqual(decoded.operation, .deposit)
        XCTAssertEqual(decoded.descriptor, KaminoVaultRegistry.allezSOL)
        XCTAssertEqual(decoded.amountBaseUnits, BigInt(500_000_000))
        XCTAssertEqual(decoded.amountDecimals, 9)
        XCTAssertEqual(decoded.amountString, "0.5")
        // The one deposit that leaves rent behind, and the reason the disclosure
        // is derived rather than passed in.
        XCTAssertTrue(decoded.strandsWrappedSolRent)
    }

    /// The withdraw's `u64` is in SHARES, at the vault's share scale — 6 here,
    /// which happens to match the token scale on this vault and does not on the
    /// SOL one. Reading it at the token scale is the mistake the whole
    /// two-amount-type design exists to prevent, so it is pinned.
    func testDecodesTheUsdcWithdrawInShares() throws {
        let decoded = try decode(KaminoTransactionFixtures.usdcWithdraw.source)

        XCTAssertEqual(decoded.operation, .withdraw)
        XCTAssertEqual(decoded.descriptor, KaminoVaultRegistry.steakhouseUSDC)
        XCTAssertEqual(decoded.amountDecimals, KaminoVaultRegistry.steakhouseUSDC.sharesDecimals)
        XCTAssertEqual(decoded.signer, KaminoTransactionFixtures.usdcWithdraw.feePayer)
        XCTAssertFalse(decoded.strandsWrappedSolRent)
    }

    /// The decode has to survive the ComputeBudget injection, because the bytes
    /// that reach a signer are always the injected ones — the pre-injection form
    /// never leaves the preparer. Injection appends a static key and shifts every
    /// account index at or above the old static count, so a decoder that read raw
    /// indices would name different accounts on the two forms.
    func testTheInjectedFormDecodesIdenticallyApartFromItsBudget() throws {
        for vector in KaminoTransactionFixtures.all {
            let source = try decode(vector.source)
            let injected = try decode(vector.injected)

            // Everything the screen SAYS is identical across the injection...
            XCTAssertEqual(source.operation, injected.operation, vector.name)
            XCTAssertEqual(source.descriptor, injected.descriptor, vector.name)
            XCTAssertEqual(source.amountBaseUnits, injected.amountBaseUnits, vector.name)
            XCTAssertEqual(source.signer, injected.signer, vector.name)
            XCTAssertEqual(source.strandsWrappedSolRent, injected.strandsWrappedSolRent, vector.name)

            // ...and the one thing that differs is the one thing injection adds,
            // which the decode must report rather than smooth over: the fee row
            // and the payload are checked against it.
            XCTAssertNil(source.priorityFee, vector.name)
            XCTAssertNotNil(injected.priorityFee, vector.name)
            XCTAssertEqual(injected.priorityFee?.limit, vector.unitLimit, vector.name)
            XCTAssertEqual(
                injected.priorityFee?.price,
                KaminoTransactionFixtures.unitPriceMicroLamports,
                vector.name
            )
        }
    }

    // MARK: - What the decoder refuses to describe

    /// The vault is identified by deriving each curated vault's share account for
    /// this signer, so a transaction whose share slot belongs to nobody we
    /// recognise cannot be named. Refusing beats showing a vault the bytes do not
    /// actually target.
    func testRefusesAShareAccountThatIsNotACuratedVaultsOwn() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let position = try XCTUnwrap(kvaultDepositPosition(in: mutable))
        // Point the share slot at the fee payer, which is a real account in this
        // transaction and is not any vault's share ATA.
        mutable.instructions[position].accounts[KaminoInstructionAccounts.KvaultDeposit.userShareAccount] = 0

        XCTAssertNil(KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64())))
    }

    /// The instruction's authority must be the transaction's own signer.
    /// Otherwise the amount and vault on screen would describe an instruction
    /// somebody else authorises, which is not what the user is approving.
    func testRefusesAnAuthorityThatIsNotTheSigner() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let position = try XCTUnwrap(kvaultDepositPosition(in: mutable))
        mutable.instructions[position].accounts[KaminoInstructionAccounts.KvaultDeposit.user] = 1

        XCTAssertNil(KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64())))
    }

    /// The bytes have to be the shape this app is willing to SIGN, not merely
    /// one it can read. The raw signing path hashes the message verbatim and
    /// replaces signature slot 0 only, so a transaction that requires a second
    /// signature would be approved on a screen describing an ordinary deposit —
    /// with whatever the other signer authorises nowhere on it. The initiator's
    /// validator asserts this before building; a relayed transaction reaches
    /// nothing but the decoder.
    func testRefusesATransactionThatRequiresMoreThanOneSignature() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        mutable.numRequiredSignatures = 2
        let base64 = try mutable.base64()

        let transaction = try SolanaV0Transaction(base64Transaction: base64)
        XCTAssertTrue(KaminoTransactionDecoder.invokesKaminoVault(transaction))
        XCTAssertNil(KaminoTransactionDecoder.decode(transaction))
        // And the screen says so, rather than falling back to an ordinary
        // Solana payload that mentions none of this.
        XCTAssertEqual(
            KaminoVerifyPresentation.state(for: payload(transaction: base64, marker: nil)),
            .unreadable
        )
    }

    /// The same for a signature slot that is already filled: the splice at index
    /// 0 assumes an empty placeholder, so bytes carrying a contribution somebody
    /// else made are not the unsigned transaction this screen claims to show.
    func testRefusesATransactionWhoseSignatureSlotIsAlreadyFilled() throws {
        let mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        var bytes = try mutable.bytes()
        // One required signature, so the compact length is a single byte and the
        // slot it counts begins immediately after it.
        bytes[1] = 0x01

        let transaction = try SolanaV0Transaction(base64Transaction: Data(bytes).base64EncodedString())
        XCTAssertTrue(KaminoTransactionDecoder.invokesKaminoVault(transaction))
        XCTAssertNil(KaminoTransactionDecoder.decode(transaction))
    }

    /// Two kvault instructions means two amounts, and picking one to display
    /// would be a guess about which the user cares about.
    func testRefusesTwoVaultInstructions() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let position = try XCTUnwrap(kvaultDepositPosition(in: mutable))
        mutable.instructions.append(mutable.instructions[position])

        let transaction = try SolanaV0Transaction(base64Transaction: mutable.base64())
        XCTAssertTrue(KaminoTransactionDecoder.invokesKaminoVault(transaction))
        XCTAssertNil(KaminoTransactionDecoder.decode(transaction))
    }

    /// A kvault instruction whose discriminator this app does not issue. The
    /// transaction is still recognisably Kamino's, so it must surface as
    /// unreadable rather than silently as an ordinary Solana transaction.
    func testAnUnknownVaultInstructionIsUnreadableRatherThanInvisible() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let position = try XCTUnwrap(kvaultDepositPosition(in: mutable))
        mutable.instructions[position].data[0] ^= 0xFF

        let transaction = try SolanaV0Transaction(base64Transaction: mutable.base64())
        XCTAssertTrue(KaminoTransactionDecoder.invokesKaminoVault(transaction))
        XCTAssertNil(KaminoTransactionDecoder.decode(transaction))
        XCTAssertEqual(
            KaminoVerifyPresentation.state(for: payload(transaction: try mutable.base64(), marker: nil)),
            .unreadable
        )
    }

    /// **The finding this decoder exists for.** A transfer riding alongside a
    /// perfectly ordinary deposit. The kvault instruction is untouched and still
    /// decodes; the transaction as a whole does not fit the shape a deposit
    /// produces, so the decode describes none of it. Summarising "Deposit 10
    /// USDC" over bytes that also move SOL somewhere else would be strictly
    /// worse than showing nothing.
    func testRefusesAnUnexplainedTransferRidingAlongsideTheDeposit() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let systemProgram = mutable.appendStaticReadonlyKey(Self.systemProgramKey)
        mutable.instructions.append(
            .init(
                programIdIndex: systemProgram,
                accounts: [0, 1],
                // System::transfer, 1 SOL.
                data: KaminoInstructionDiscriminator.systemTransfer + [0, 202, 154, 59, 0, 0, 0, 0]
            )
        )

        let transaction = try SolanaV0Transaction(base64Transaction: mutable.base64())
        XCTAssertTrue(KaminoTransactionDecoder.invokesKaminoVault(transaction))
        XCTAssertNil(KaminoTransactionDecoder.decode(transaction))
        XCTAssertEqual(
            KaminoVerifyPresentation.state(for: payload(transaction: try mutable.base64(), marker: nil)),
            .unreadable
        )
    }

    /// The same for a USDC deposit that carries a wrap step. It is a legitimate
    /// instruction for the SOL vault and has no business in a token vault's
    /// transaction, which is exactly what makes the per-vault template do work.
    func testRefusesAWrapStepInATokenVaultDeposit() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let systemProgram = mutable.appendStaticReadonlyKey(Self.systemProgramKey)
        mutable.instructions.insert(
            .init(
                programIdIndex: systemProgram,
                accounts: [0, 1],
                data: KaminoInstructionDiscriminator.systemTransfer + [0, 202, 154, 59, 0, 0, 0, 0]
            ),
            at: 0
        )

        XCTAssertNil(KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64())))
    }

    /// Detection reads the bytes, never the relayed `coin.chain`. Gating on that
    /// field would let whoever supplied it switch the decode off — and it is
    /// supplied by the same device that supplied the bytes.
    func testARelayedChainCannotSuppressTheDecode() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: nil,
                chain: .ethereum
            )
        )

        XCTAssertNotEqual(state, .notKamino)
        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .asset))
    }

    /// The coin the summary scales `toAmount` with must be the vault's own
    /// asset. A 9-decimal coin against a 6-decimal vault renders the headline
    /// figure a thousandfold out.
    func testACoinThatIsNotTheVaultsAssetIsAMismatch() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                toAmount: BigInt(10_000_000),
                // Native SOL against a USDC vault.
                contractAddress: "",
                decimals: 9,
                ticker: "SOL"
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .asset))
    }

    /// The summary renders this block only when it has something to say, and a
    /// verified token deposit does not: its vault, curator and action are rows
    /// above, its amount is the headline, and it strands no rent. Rendering it
    /// regardless left a separator and an empty band under the fee row.
    ///
    /// The three states that warn about something always render, and so does a
    /// withdraw — its bytes are in shares, which no other row on the screen says.
    func testAVerifiedTokenDepositHasNothingLeftToRender() throws {
        let deposit = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                toAmount: BigInt(10_000_000)
            )
        )
        XCTAssertEqual(deposit, .verified(try XCTUnwrap(deposit.display)))
        XCTAssertFalse(deposit.hasVisibleDetail)

        // The SOL deposit is verified too, but strands wrapped-SOL rent — a
        // disclosure that exists nowhere else on this screen.
        let native = try XCTUnwrap(DefiPositionsService.nativeSolanaMeta)
        let solDeposit = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.solDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.allezSOL.address,
                toAmount: BigInt(500_000_000),
                contractAddress: native.contractAddress,
                decimals: native.decimals,
                ticker: native.ticker,
                priorityLimit: KaminoComputeBudget.nativeDepositUnitLimit
            )
        )
        XCTAssertTrue(solDeposit.hasVisibleDetail)

        XCTAssertTrue(KaminoVerifyPresentation.State.unreadable.hasVisibleDetail)
        XCTAssertFalse(KaminoVerifyPresentation.State.notKamino.hasVisibleDetail)
    }

    /// The asset check must not refuse the SOL vault. Its underlying mint is
    /// WRAPPED SOL, which the wallet never holds as a coin — the transaction
    /// wraps native SOL itself — so the coin on the payload is native SOL and
    /// the registry maps the vault to it. A check that compared the raw mint
    /// would refuse every legitimate SOL deposit.
    func testTheWrappedSolVaultVerifiesAgainstTheNativeSolCoin() throws {
        let native = try XCTUnwrap(DefiPositionsService.nativeSolanaMeta)
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.solDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.allezSOL.address,
                toAmount: BigInt(500_000_000),
                contractAddress: native.contractAddress,
                decimals: native.decimals,
                ticker: native.ticker,
                priorityLimit: KaminoComputeBudget.nativeDepositUnitLimit
            )
        )

        XCTAssertEqual(state, .verified(try XCTUnwrap(state.display)))
        XCTAssertEqual(state.display?.vaultName, KaminoVaultRegistry.allezSOL.fallbackName)
        XCTAssertEqual(state.display?.amount, "0.5")
        // And the rent disclosure the form shows is repeated here, because a
        // co-signer never saw the form.
        XCTAssertTrue(state.display?.strandsWrappedSolRent == true)
    }

    /// `u64::MAX` is the API's "withdraw everything" sentinel, not a share count.
    /// This app cannot produce one, but a co-signer holds only relayed bytes —
    /// and 18,446,744,073,709.551615 shares would be literally true and say
    /// nothing about what the transaction does.
    func testTheWithdrawEverythingSentinelIsNamedRatherThanCounted() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcWithdraw.source)
        let position = try XCTUnwrap(
            mutable.instructions.firstIndex {
                Array($0.data.prefix(8)) == KaminoInstructionDiscriminator.kvaultWithdraw
            }
        )
        mutable.instructions[position].data.replaceSubrange(8..<16, with: [UInt8](repeating: 0xFF, count: 8))

        let decoded = try XCTUnwrap(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64()))
        )
        XCTAssertTrue(decoded.withdrawsEntirePosition)

        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: try mutable.base64(),
                marker: nil,
                toAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                coinAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                // Built from the SOURCE vector, which carries no ComputeBudget,
                // so the payload must record none either.
                priorityLimit: 0
            )
        )
        let display = try XCTUnwrap(state.display)
        XCTAssertEqual(display.amountWithUnit, "kaminoVerifyEntirePosition".localized)
        XCTAssertFalse(display.amountWithUnit.contains("18446744073709"))
    }

    /// Bytes the v0 parser refuses are still bytes the raw Solana path would
    /// SIGN — it hashes the wire message verbatim and does not care what version
    /// it is. So an unparseable payload that mentions the kVaults program is
    /// unreadable, not invisible.
    func testUnparseableBytesMentioningTheVaultProgramAreUnreadable() throws {
        // A legacy (non-versioned) message: no 0x80 version byte, so the v0
        // parser refuses it, carrying the kVaults program id as a static key.
        var wire: [UInt8] = [1]
        wire += [UInt8](repeating: 0, count: 64)
        wire += [1, 0, 1]
        wire += [2]
        wire += [UInt8](repeating: 7, count: 32)
        wire += [UInt8](try XCTUnwrap(Base58.decodeNoCheck(string: KaminoVaultRegistry.programId)))
        wire += [UInt8](repeating: 9, count: 32)
        wire += [0]
        let base64 = Data(wire).base64EncodedString()

        XCTAssertNil(try? SolanaV0Transaction(base64Transaction: base64))
        XCTAssertTrue(KaminoTransactionDecoder.mentionsKaminoVaultProgram(base64Transaction: base64))

        let state = KaminoVerifyPresentation.state(for: payload(transaction: base64, marker: nil))
        XCTAssertEqual(state, .unreadable)
        XCTAssertTrue(state.blocksSigning)
    }

    /// And bytes that neither parse nor mention the program leave every other
    /// flow exactly as it was.
    func testUnparseableBytesWithoutTheVaultProgramStayNotKamino() {
        XCTAssertEqual(
            KaminoVerifyPresentation.state(for: payload(transaction: "bm90LWEtdHJhbnNhY3Rpb24=", marker: nil)),
            .notKamino
        )
    }

    /// Matching the template is not the same as accepting the numbers. The
    /// priority fee is `limit × price` micro-lamports out of the payer's balance,
    /// bounded on chain by nothing else — and both halves are plain integers in
    /// the instruction data, so an inflated one is readable offline and refused.
    func testRefusesAComputeUnitPriceAboveWhatThisAppWouldEverInject() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.injected)
        let position = try XCTUnwrap(
            mutable.instructions.firstIndex { $0.data.first == ComputeBudgetInstruction.setUnitPrice }
        )
        var inflated: [UInt8] = [ComputeBudgetInstruction.setUnitPrice]
        inflated += withUnsafeBytes(of: UInt64.max.littleEndian) { [UInt8]($0) }
        mutable.instructions[position].data = inflated

        let transaction = try SolanaV0Transaction(base64Transaction: mutable.base64())
        XCTAssertTrue(KaminoTransactionDecoder.invokesKaminoVault(transaction))
        XCTAssertNil(KaminoTransactionDecoder.decode(transaction))
    }

    /// A SOL deposit's wrap transfer is the only native SOL movement in the whole
    /// operation, and all three of its parts are readable offline: the amount
    /// must equal the deposit, the source must be the signer, and the destination
    /// must be the signer's own wrapped-SOL account, which is derived locally.
    func testRefusesAWrapTransferForAnAmountOtherThanTheDeposit() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.solDeposit.source)
        let position = try XCTUnwrap(
            mutable.instructions.firstIndex {
                Array($0.data.prefix(4)) == KaminoInstructionDiscriminator.systemTransfer
            }
        )
        // The template still matches; only the lamports changed.
        var data = mutable.instructions[position].data
        data.replaceSubrange(4..<12, with: withUnsafeBytes(of: UInt64(999).littleEndian) { [UInt8]($0) })
        mutable.instructions[position].data = data

        XCTAssertNil(KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64())))
    }

    func testRefusesAWrapTransferToAnAccountThatIsNotTheSignersOwn() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.solDeposit.source)
        let position = try XCTUnwrap(
            mutable.instructions.firstIndex {
                Array($0.data.prefix(4)) == KaminoInstructionDiscriminator.systemTransfer
            }
        )
        // Static key 1 is a real account in this transaction and is not the
        // user's wrapped-SOL account.
        mutable.instructions[position].accounts[KaminoInstructionAccounts.SystemTransfer.destination] = 1

        XCTAssertNil(KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64())))
    }

    /// The hero reads "You're sending <amount> <coin.ticker>", so a payload
    /// carrying the right mint under a false ticker puts a true number beside the
    /// wrong asset name.
    func testACoinWithTheRightMintButAFalseTickerIsAMismatch() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                toAmount: BigInt(10_000_000),
                ticker: "BTC"
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .asset))
    }

    /// Stripping the injected ComputeBudget selects the PRE-injection template,
    /// which still matches — so the sequence alone would call it verified while
    /// the fee row above quotes a priority fee the transaction does not pay. The
    /// initiating device's validator refuses exactly this shape, so a co-signer
    /// accepting it would be the weaker of the two.
    func testStrippingTheComputeBudgetIsAMismatchAgainstTheRecordedFee() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.injected)
        mutable.instructions.removeAll {
            $0.data.first == ComputeBudgetInstruction.setUnitLimit
                || $0.data.first == ComputeBudgetInstruction.setUnitPrice
        }

        // It still decodes — that is the point of the finding.
        let decoded = try XCTUnwrap(
            KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64()))
        )
        XCTAssertNil(decoded.priorityFee)

        // But the payload records a budget, so the two disagree.
        let state = KaminoVerifyPresentation.state(
            for: payload(transaction: try mutable.base64(), marker: nil)
        )
        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .priorityFee))
        XCTAssertTrue(state.blocksSigning)
    }

    /// The compute unit limit is pinned to the value this app injects for THIS
    /// operation and vault, not merely bounded — the app emits exactly one, so
    /// any other did not come from it.
    func testRefusesAComputeUnitLimitThisAppWouldNotHaveInjected() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.injected)
        let position = try XCTUnwrap(
            mutable.instructions.firstIndex { $0.data.first == ComputeBudgetInstruction.setUnitLimit }
        )
        var data: [UInt8] = [ComputeBudgetInstruction.setUnitLimit]
        // The SOL vault's limit, on a USDC vault's deposit.
        data += withUnsafeBytes(of: KaminoComputeBudget.nativeDepositUnitLimit.littleEndian) { [UInt8]($0) }
        mutable.instructions[position].data = data

        XCTAssertNil(KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64())))
    }

    /// `farms::stake` takes `u64::MAX`, meaning "stake the whole share balance".
    /// A specific amount is a behaviour change, not a variation — the validator
    /// refuses it on the initiator and the decoder must refuse it on a peer.
    func testRefusesAFarmStakeForAnythingOtherThanTheWholeBalance() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let position = try XCTUnwrap(
            mutable.instructions.firstIndex {
                Array($0.data.prefix(8)) == KaminoInstructionDiscriminator.farmsStake
            }
        )
        var data = mutable.instructions[position].data
        data.replaceSubrange(8..<16, with: withUnsafeBytes(of: UInt64(1).littleEndian) { [UInt8]($0) })
        mutable.instructions[position].data = data

        XCTAssertNil(KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64())))
    }

    /// Account cardinality is readable offline even though identity is not, and
    /// an instruction with too few accounts to be what it claims is malformed.
    func testRefusesAFarmStakeWithTooFewAccounts() throws {
        var mutable = try MutableTransaction(base64: KaminoTransactionFixtures.usdcDeposit.source)
        let position = try XCTUnwrap(
            mutable.instructions.firstIndex {
                Array($0.data.prefix(8)) == KaminoInstructionDiscriminator.farmsStake
            }
        )
        mutable.instructions[position].accounts.removeLast(3)

        XCTAssertNil(KaminoTransactionDecoder.decode(try SolanaV0Transaction(base64Transaction: mutable.base64())))
    }

    /// The injected vectors carry the budget this app emits, so they read back
    /// as exactly that — the positive side of the two tests above.
    func testTheInjectedVectorsReportTheirOwnComputeBudget() throws {
        let deposit = try decode(KaminoTransactionFixtures.usdcDeposit.injected)
        XCTAssertEqual(
            deposit.priorityFee,
            KaminoPriorityFee(
                limit: KaminoComputeBudget.tokenDepositUnitLimit,
                price: KaminoTransactionFixtures.unitPriceMicroLamports
            )
        )
        let solDeposit = try decode(KaminoTransactionFixtures.solDeposit.injected)
        XCTAssertEqual(solDeposit.priorityFee?.limit, KaminoComputeBudget.nativeDepositUnitLimit)
        let withdraw = try decode(KaminoTransactionFixtures.usdcWithdraw.injected)
        XCTAssertEqual(withdraw.priorityFee?.limit, KaminoComputeBudget.withdrawUnitLimit)
    }

    // MARK: - Refusing to sign

    /// A mismatch and an unreadable Kamino transaction both block signing. A
    /// rendered warning that leaves the button enabled makes the whole check
    /// advisory, which is the posture this feature exists to replace.
    func testAMismatchAndAnUnreadableTransactionBothBlockSigning() throws {
        let mismatch = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.rwaUSDC.address,
                toAmount: BigInt(10_000_000)
            )
        )
        XCTAssertTrue(mismatch.blocksSigning)

        XCTAssertTrue(KaminoVerifyPresentation.State.unreadable.blocksSigning)
        XCTAssertFalse(KaminoVerifyPresentation.State.notKamino.blocksSigning)
    }

    /// A co-signer's withdraw is not "verified" — the amount the summary leads
    /// with is a token projection at a rate that never travelled, so nothing on
    /// this device checked it. It is also not a refusal: refusing would break
    /// every legitimate peer withdraw. It is its own answer, and it does not
    /// block signing.
    func testACoSignersWithdrawIsAmountUnverifiableRatherThanVerified() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcWithdraw.injected,
                marker: nil,
                toAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                toAmount: BigInt(1_082_517),
                coinAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                priorityLimit: KaminoComputeBudget.withdrawUnitLimit
            )
        )

        XCTAssertEqual(state, .amountUnverifiable(try XCTUnwrap(state.display)))
        XCTAssertFalse(state.blocksSigning)
    }

    /// The INITIATOR's withdraw is fully verified, because it holds the marker
    /// and the marker records the share figure the bytes carry.
    func testTheInitiatorsWithdrawIsFullyVerified() throws {
        let decoded = try decode(KaminoTransactionFixtures.usdcWithdraw.injected)
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcWithdraw.injected,
                marker: KaminoKeysignPayload(
                    vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                    operation: .withdraw,
                    amount: KaminoShareAmount(
                        baseUnits: decoded.amountBaseUnits,
                        decimals: KaminoVaultRegistry.steakhouseUSDC.sharesDecimals
                    )
                ),
                toAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                coinAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                priorityLimit: KaminoComputeBudget.withdrawUnitLimit
            )
        )

        XCTAssertEqual(state, .verified(try XCTUnwrap(state.display)))
    }

    /// Nothing else changes. A payload with no Solana bytes, or Solana bytes that
    /// never touch the kVaults program, renders exactly as it did before.
    func testANonKaminoPayloadIsUntouched() {
        XCTAssertEqual(KaminoVerifyPresentation.state(for: nil), .notKamino)
    }

    /// A Kamino transaction smuggled into a batch alongside another one. The
    /// summary can only describe one transaction, so describing the wrong one —
    /// or, worse, going quiet — is not available: this surfaces as unreadable.
    /// Nothing this app builds sends a batch, which is exactly why an unexpected
    /// one has to fail closed.
    func testAKaminoTransactionInABatchIsUnreadableRatherThanSilent() {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transactions: [
                    KaminoTransactionFixtures.usdcDeposit.injected,
                    KaminoTransactionFixtures.usdcWithdraw.injected
                ],
                marker: nil
            )
        )

        XCTAssertEqual(state, .unreadable)
    }

    /// And a Kamino transaction alongside bytes that will not parse at all. The
    /// unparseable half must not be what decides the rendering.
    func testAKaminoTransactionBesideUnparseableBytesIsUnreadable() {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transactions: [KaminoTransactionFixtures.usdcDeposit.injected, "not-base64-at-all"],
                marker: nil
            )
        )

        XCTAssertEqual(state, .unreadable)
    }

    // MARK: - The cross-check on the initiator

    /// The initiator holds the marker, so all three fields are comparable and all
    /// three are compared.
    func testTheInitiatorVerifiesAgainstItsOwnMarker() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: KaminoKeysignPayload(
                    vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                    operation: .deposit,
                    amount: KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 6)
                )
            )
        )

        let display = try XCTUnwrap(state.display)
        XCTAssertFalse(state.isMismatch)
        XCTAssertEqual(display.vaultName, KaminoVaultRegistry.steakhouseUSDC.fallbackName)
        XCTAssertEqual(display.amount, "10")
        XCTAssertEqual(display.unit, "USDC")
        XCTAssertEqual(display.curator, KaminoVaultRegistry.steakhouseUSDC.curator)
        XCTAssertEqual(display.riskTier, .conservative)
    }

    /// A marker that names a different amount from the bytes is the case this
    /// whole screen exists for: the summary above would show the marker's number
    /// and the network would charge the bytes'. It is a refusal, and the decode
    /// is still shown, because the decode is what gets signed.
    func testAMarkerAmountThatDisagreesWithTheBytesIsAMismatch() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: KaminoKeysignPayload(
                    vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                    operation: .deposit,
                    amount: KaminoTokenAmount(baseUnits: BigInt(10_000_001), decimals: 6)
                )
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .amount))
        XCTAssertEqual(state.display?.amount, "10")
    }

    func testAMarkerVaultThatDisagreesWithTheBytesIsAMismatch() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: KaminoKeysignPayload(
                    vaultAddress: KaminoVaultRegistry.rwaUSDC.address,
                    operation: .deposit,
                    amount: KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 6)
                )
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .vault))
    }

    func testAMarkerOperationThatDisagreesWithTheBytesIsAMismatch() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: KaminoKeysignPayload(
                    vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                    operation: .withdraw,
                    amount: KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 6)
                )
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .operation))
    }

    /// The account that pays for and authorises the transaction is the fee payer
    /// in the bytes; the summary's "from" row is `payload.coin.address`. A
    /// signature by the vault's key only settles for a transaction the vault
    /// pays for, so this cannot spend somebody else's balance — but it can put an
    /// account on screen that has nothing to do with what is being signed, and
    /// that is checked on BOTH devices before anything else.
    func testASignerThatIsNotTheAccountOnScreenIsAMismatch() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: KaminoKeysignPayload(
                    vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                    operation: .deposit,
                    amount: KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 6)
                ),
                // The withdraw vector's fee payer — a real Solana account, and
                // not the one these bytes pay from.
                coinAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                priorityLimit: KaminoComputeBudget.withdrawUnitLimit
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .signer))
    }

    // MARK: - The cross-check on a co-signer

    /// A co-signer has no marker — it never crosses the wire — so it checks the
    /// values that do. For a deposit both the destination and the amount are
    /// exactly comparable.
    func testACoSignerVerifiesADepositAgainstTheTravellingFields() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                toAmount: BigInt(10_000_000)
            )
        )

        XCTAssertFalse(state.isMismatch)
        XCTAssertEqual(state.display?.amount, "10")
    }

    /// The marker really is absent after a proto round trip, so the co-signer
    /// path above is the one a peer device takes — not a hypothetical.
    func testTheMarkerDoesNotSurviveTheProtoRoundTrip() throws {
        let original = payload(
            transaction: KaminoTransactionFixtures.usdcDeposit.injected,
            marker: KaminoKeysignPayload(
                vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                operation: .deposit,
                amount: KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 6)
            ),
            toAddress: KaminoVaultRegistry.steakhouseUSDC.address,
            toAmount: BigInt(10_000_000)
        )

        let relayed = try KeysignPayload(proto: original.mapToProtobuff())

        XCTAssertNil(relayed.kaminoPayload)
        XCTAssertEqual(relayed.signSolana?.rawTransactions, original.signSolana?.rawTransactions)
        // And the decode still lands, from the bytes alone.
        let state = KaminoVerifyPresentation.state(for: relayed)
        XCTAssertFalse(state.isMismatch)
        XCTAssertEqual(state.display?.amount, "10")
    }

    /// A co-signer shown "10 USDC to the vault" over bytes that deposit something
    /// else must refuse. This is the attack the decode is for: the summary rows a
    /// peer sees are rebuilt from `toAddress`/`toAmount`, which the relaying
    /// device supplies.
    func testACoSignerRefusesADepositWhoseSummaryAmountIsNotInTheBytes() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.steakhouseUSDC.address,
                toAmount: BigInt(1)
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .amount))
    }

    func testACoSignerRefusesADepositAimedAtAnotherVaultThanTheSummarySays() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcDeposit.injected,
                marker: nil,
                toAddress: KaminoVaultRegistry.rwaUSDC.address,
                toAmount: BigInt(10_000_000)
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .destination))
    }

    /// A withdraw pays the user's own account, so THAT is what a co-signer can
    /// check. Its `toAmount` is a token projection of a share figure at a rate
    /// that never crossed the wire, so it is deliberately not compared — and the
    /// display names the unit so the two numbers do not read as a contradiction.
    func testACoSignerChecksAWithdrawsDestinationAndNamesTheShareUnit() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcWithdraw.injected,
                marker: nil,
                toAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                // The token projection, which is NOT the share figure in the
                // bytes. A check that compared these would refuse every real
                // withdraw.
                toAmount: BigInt(1_082_517),
                coinAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                priorityLimit: KaminoComputeBudget.withdrawUnitLimit
            )
        )

        XCTAssertFalse(state.isMismatch)
        XCTAssertEqual(state.display?.operation, .withdraw)
        XCTAssertEqual(state.display?.unit, "kaminoVerifyShares".localized)
    }

    func testACoSignerRefusesAWithdrawThatPaysSomebodyElse() throws {
        let state = KaminoVerifyPresentation.state(
            for: payload(
                transaction: KaminoTransactionFixtures.usdcWithdraw.injected,
                marker: nil,
                toAddress: KaminoTransactionFixtures.usdcDeposit.feePayer,
                toAmount: BigInt(1_082_517),
                coinAddress: KaminoTransactionFixtures.usdcWithdraw.feePayer,
                priorityLimit: KaminoComputeBudget.withdrawUnitLimit
            )
        )

        XCTAssertEqual(state, .mismatch(try XCTUnwrap(state.display), .destination))
    }

    // MARK: - Helpers

    /// The System program's 32 all-zero bytes.
    private static let systemProgramKey = [UInt8](repeating: 0, count: 32)

    private func decode(_ base64: String) throws -> KaminoDecodedTransaction {
        let transaction = try SolanaV0Transaction(base64Transaction: base64)
        XCTAssertTrue(KaminoTransactionDecoder.invokesKaminoVault(transaction))
        return try XCTUnwrap(KaminoTransactionDecoder.decode(transaction))
    }

    private func kvaultDepositPosition(in mutable: MutableTransaction) -> Int? {
        mutable.instructions.firstIndex {
            Array($0.data.prefix(8)) == KaminoInstructionDiscriminator.kvaultDeposit
        }
    }

    private func payload(
        transaction: String,
        marker: KaminoKeysignPayload?,
        toAddress: String = "",
        toAmount: BigInt = 0,
        coinAddress: String = KaminoTransactionFixtures.usdcDeposit.feePayer,
        chain: Chain = .solana,
        contractAddress: String = KaminoVaultRegistry.usdcMint,
        decimals: Int = 6,
        ticker: String = "USDC",
        priorityLimit: UInt32 = KaminoComputeBudget.tokenDepositUnitLimit
    ) -> KeysignPayload {
        payload(
            transactions: [transaction],
            marker: marker,
            toAddress: toAddress,
            toAmount: toAmount,
            coinAddress: coinAddress,
            chain: chain,
            contractAddress: contractAddress,
            decimals: decimals,
            ticker: ticker,
            priorityLimit: priorityLimit
        )
    }

    private func payload(
        transactions: [String],
        marker: KaminoKeysignPayload?,
        toAddress: String = "",
        toAmount: BigInt = 0,
        coinAddress: String = KaminoTransactionFixtures.usdcDeposit.feePayer,
        chain: Chain = .solana,
        contractAddress: String = KaminoVaultRegistry.usdcMint,
        decimals: Int = 6,
        ticker: String = "USDC",
        /// Mirrors what the initiating device injected. It has to MATCH the
        /// vector's own ComputeBudget or the payload and the bytes disagree —
        /// which is the point of the check, and means each vector's own limit
        /// has to be named here.
        priorityLimit: UInt32 = KaminoComputeBudget.tokenDepositUnitLimit
    ) -> KeysignPayload {
        KeysignPayload(
            coin: Coin(
                asset: CoinMeta(
                    chain: chain,
                    ticker: ticker,
                    logo: "usdc",
                    decimals: decimals,
                    priceProviderId: "usd-coin",
                    contractAddress: contractAddress,
                    isNativeToken: contractAddress.isEmpty
                ),
                address: coinAddress,
                hexPublicKey: ""
            ),
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Solana(
                recentBlockHash: "",
                priorityFee: priorityLimit == 0 ? 0 : BigInt(KaminoTransactionFixtures.unitPriceMicroLamports),
                priorityLimit: BigInt(priorityLimit),
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "ecdsa",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            kaminoPayload: marker,
            skipBroadcast: false,
            signData: .signSolana(SignSolana(rawTransactions: transactions))
        )
    }
}
