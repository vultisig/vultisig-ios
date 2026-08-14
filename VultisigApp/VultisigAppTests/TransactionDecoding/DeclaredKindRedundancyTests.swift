//
//  DeclaredKindRedundancyTests.swift
//  VultisigAppTests
//
//  Which builder-declared `functionKind`s the decoder makes redundant.
//
//  Every builder that names a kind is declaring something the transaction may
//  already say for itself. Where the decoder derives the same operation from
//  signed content, the declaration is dead weight — and dead weight that has not
//  merged yet is better removed than merged and deleted later.
//
//  ⚠️ This is the evidence for those removals, not a general decoder test. Each
//  case reproduces what a real builder emits, decoded through the INITIATOR's
//  surface, because that is the side the declaration exists for. A case that
//  fails here means the declaration is load-bearing and must stay.
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import XCTest

@MainActor
final class DeclaredKindRedundancyTests: XCTestCase {

    /// Operations the initiator can read off its own transaction.
    ///
    /// Each row is `(what the builder emits, the chain it is emitted on, the
    /// kind that builder declares)`. Passing means the declaration adds nothing.
    func testTheDecoderDerivesTheseWithoutADeclaration() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let cases: [(memo: String, chain: Chain, declared: FunctionTransactionKind)] = [
            ("tcy+", .thorChain, .stake),
            ("tcy-:5006", .thorChain, .unstake),
            ("BOND:thor1node", .thorChain, .bond),
            ("UNBOND:thor1node:150000000", .thorChain, .unbond),
            ("bond:thor1contract:250000000", .thorChain, .stake),
            ("withdraw:thor1contract:250000000", .thorChain, .unstake),
            ("claim:thor1contract:250000000", .thorChain, .claimRewards),
            ("pool+", .mayaChain, .stake),
            ("POOL-:5000", .mayaChain, .unstake)
        ]

        for row in cases {
            let decoded = SignedTransactionDecoder.decode(
                InitiatingTransactionContent(
                    makeTransaction(memo: row.memo, chain: row.chain)
                )
            )
            XCTAssertEqual(
                decoded.operation,
                expected(for: row.declared),
                "\(row.memo) on \(row.chain): declaration is NOT redundant"
            )
        }
    }

    /// ⚠️ Operations whose declaration is load-bearing, and why.
    ///
    /// THORChain's inbound memos need signed corroboration that a THORChain
    /// vault is the destination, and an initiator has none yet — the router shim
    /// that provides it is synthesized during payload construction, after the
    /// screen has already rendered. So an LP add leaving Bitcoin or Ethereum
    /// decodes to nothing on the initiator, and its builder must keep saying
    /// what it is.
    func testAnInboundMemoIsNotDerivableOnTheInitiator() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let decoded = SignedTransactionDecoder.decode(
            InitiatingTransactionContent(makeTransaction(memo: "+:BTC.BTC", chain: .bitcoin))
        )
        XCTAssertEqual(
            decoded.operation, .unknown,
            "if this becomes derivable, the LP builders' declarations can go too"
        )
    }

    /// ⚠️ And the other load-bearing set: operations whose intent rides opaque
    /// signed content. A Cosmos delegate carries no memo at all — the decoder
    /// refuses it by design, so only the builder can say what it is.
    func testAnOpaqueSignedOperationIsNotDerivable() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let decoded = SignedTransactionDecoder.decode(
            InitiatingTransactionContent(makeTransaction(
                memo: "",
                chain: .gaiaChain,
                cosmosStaking: .delegate(
                    validator: "cosmosvaloper1x", denom: "uatom", amount: "100000000"
                )
            ))
        )
        XCTAssertEqual(decoded.operation, .unknown)
    }

    // MARK: - Fixtures

    private func expected(for kind: FunctionTransactionKind) -> DecodedOperation {
        switch kind {
        case .stake: return .stake
        case .unstake: return .unstake
        case .bond: return .bond
        case .unbond: return .unbond
        case .delegate: return .delegate
        case .undelegate: return .undelegate
        case .redelegate: return .redelegate
        case .claimRewards: return .claimRewards
        case .mint: return .mint
        case .redeem: return .redeem
        case .addLiquidity: return .addLiquidity
        case .removeLiquidity: return .removeLiquidity
        }
    }

    /// ⚠️ One vault identity per memo. These tables build several transactions
    /// inside a single container, and `Vault`'s unique attributes make a second
    /// fixture with the same key upsert over the first rather than sit beside
    /// it. Derived from the memo rather than hashed, so a failure names the row
    /// that produced it.
    private func makeTransaction(
        memo: String,
        chain: Chain,
        cosmosStaking: CosmosStakingPayload? = nil
    ) -> SendTransaction {
        let coin = Coin(
            asset: CoinMeta(
                chain: chain, ticker: "TCY", logo: "tcy", decimals: 8,
                priceProviderId: "tcy", contractAddress: "", isNativeToken: false
            ),
            address: "from1",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )

        return SendTransaction(
            coin: coin,
            vault: TestStore.makeVault(pubKey: "test-pub-redundancy-\(memo)-\(chain)"),
            fromAddress: coin.address,
            toAddress: "to1",
            toAddressLabel: nil,
            amount: "1",
            amountInFiat: "0",
            memo: memo,
            gas: .zero,
            fee: .zero,
            feeMode: .normal,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: true,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin,
            cosmosStakingPayload: cosmosStaking
        )
    }
}
